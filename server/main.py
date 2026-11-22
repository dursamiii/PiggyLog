import asyncio
import hashlib
import logging
import math
import os
import secrets
import sqlite3
from collections.abc import Iterator
from contextlib import asynccontextmanager, contextmanager
from datetime import UTC, date as date_type, datetime, timedelta
from pathlib import Path
from typing import Literal, Protocol

import httpx
from fastapi import Depends, FastAPI, HTTPException, Response, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, ConfigDict, Field, model_validator

logger = logging.getLogger("piggylog")

Asset = Literal["idr", "sar", "usd", "gold"]
GRAMS_PER_TROY_OUNCE = 31.1034768
PRICE_REFRESH_INTERVAL_SECONDS = 30 * 60


class PriceProvider(Protocol):
    async def fetch_exchange_rates(
        self, rate_date: str = "latest"
    ) -> dict[str, float]: ...

    async def fetch_gold_usd_per_gram(self) -> float: ...


class LivePriceProvider:
    def __init__(self, client: httpx.AsyncClient | None = None) -> None:
        self._client = client

    async def fetch_exchange_rates(
        self, rate_date: str = "latest"
    ) -> dict[str, float]:
        if rate_date != "latest":
            try:
                parsed_date = date_type.fromisoformat(rate_date)
            except ValueError as error:
                raise ValueError("Exchange-rate date must use YYYY-MM-DD") from error
            if parsed_date.isoformat() != rate_date:
                raise ValueError("Exchange-rate date must use YYYY-MM-DD")

        urls = (
            f"https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@{rate_date}/v1/currencies/idr.json",
            f"https://{rate_date}.currency-api.pages.dev/v1/currencies/idr.json",
        )
        errors: list[Exception] = []
        for url in urls:
            try:
                payload = await self._get_json(url)
                return self._parse_exchange_rates(payload, rate_date)
            except (httpx.HTTPError, ValueError, KeyError, TypeError, ZeroDivisionError) as error:
                errors.append(error)
                logger.warning("Exchange-rate request failed for %s: %s", url, error)

        raise ValueError(
            f"Unable to load exchange rates for {rate_date} from both exchange-api URLs"
        ) from errors[-1]

    async def _get_json(self, url: str) -> object:
        if self._client is not None:
            response = await self._client.get(url)
        else:
            async with httpx.AsyncClient(timeout=12) as client:
                response = await client.get(url)
        response.raise_for_status()
        return response.json()

    @staticmethod
    def _parse_exchange_rates(payload: object, requested_date: str) -> dict[str, float]:
        if not isinstance(payload, dict):
            raise ValueError("Exchange-api response must be a JSON object")
        if requested_date != "latest" and payload.get("date") != requested_date:
            raise ValueError(
                f"Exchange-api returned {payload.get('date')!r} for {requested_date}"
            )
        idr_rates = payload.get("idr")
        if not isinstance(idr_rates, dict):
            raise ValueError("Exchange-api response did not contain IDR rates")
        try:
            usd_per_idr = float(idr_rates["usd"])
            sar_per_idr = float(idr_rates["sar"])
            idr_per_usd = 1 / usd_per_idr
            idr_per_sar = 1 / sar_per_idr
        except (KeyError, TypeError, ValueError, ZeroDivisionError) as error:
            raise ValueError("Exchange-api response did not contain valid USD/SAR rates") from error
        if not all(
            math.isfinite(value) and value > 0
            for value in (idr_per_usd, idr_per_sar)
        ):
            raise ValueError("Exchange-api response contained non-positive or invalid rates")
        return {"idr": 1.0, "usd": idr_per_usd, "sar": idr_per_sar}

    async def fetch_gold_usd_per_gram(self) -> float:
        async with httpx.AsyncClient(timeout=12) as client:
            response = await client.get("https://api.gold-api.com/price/XAU")
            response.raise_for_status()
            payload = response.json()

        try:
            usd_per_ounce = float(payload["price"])
        except (KeyError, TypeError, ValueError) as error:
            raise ValueError("Gold-price response did not contain a valid price") from error
        if usd_per_ounce <= 0:
            raise ValueError("Gold-price response contained a non-positive price")
        return usd_per_ounce / GRAMS_PER_TROY_OUNCE


class EntryCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    asset: Asset
    amount: float = Field(gt=0, allow_inf_nan=False)
    source: str = Field(default="", max_length=200)
    date: datetime = Field(default_factory=lambda: datetime.now(UTC))
    cost_basis_idr: float | None = Field(default=None, gt=0, allow_inf_nan=False)


class ConversionCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    from_asset: Asset
    to_asset: Asset
    amount: float = Field(gt=0, allow_inf_nan=False)
    date: datetime = Field(default_factory=lambda: datetime.now(UTC))

    @model_validator(mode="after")
    def assets_must_differ(self) -> "ConversionCreate":
        if self.from_asset == self.to_asset:
            raise ValueError("Source and destination assets must differ")
        return self


class LoginRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    username: str = Field(min_length=1, max_length=100)
    password: str = Field(min_length=1, max_length=200)


class Database:
    def __init__(self, path: Path) -> None:
        self.path = path

    @contextmanager
    def connect(self) -> Iterator[sqlite3.Connection]:
        connection = sqlite3.connect(self.path, timeout=10)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        try:
            with connection:
                yield connection
        finally:
            connection.close()

    def initialize(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.connect() as connection:
            connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS entries (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    asset TEXT NOT NULL,
                    amount REAL NOT NULL,
                    source TEXT NOT NULL DEFAULT '',
                    date TEXT NOT NULL,
                    cost_basis_idr REAL NOT NULL,
                    kind TEXT NOT NULL DEFAULT 'saving',
                    created_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS conversions (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    from_asset TEXT NOT NULL,
                    from_amount REAL NOT NULL,
                    to_asset TEXT NOT NULL,
                    to_amount REAL NOT NULL,
                    source_value_idr REAL NOT NULL,
                    target_value_idr REAL NOT NULL,
                    cost_basis_idr REAL NOT NULL,
                    realized_profit_idr REAL NOT NULL,
                    date TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS price_snapshots (
                    symbol TEXT PRIMARY KEY,
                    idr_per_unit REAL NOT NULL,
                    source TEXT NOT NULL,
                    fetched_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS historical_price_snapshots (
                    date TEXT NOT NULL,
                    symbol TEXT NOT NULL,
                    idr_per_unit REAL NOT NULL,
                    source TEXT NOT NULL,
                    fetched_at TEXT NOT NULL,
                    PRIMARY KEY (date, symbol)
                );
                CREATE TABLE IF NOT EXISTS sessions (
                    token_hash TEXT PRIMARY KEY,
                    expires_at TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );
                """
            )

    def create_session(self, token: str, expires_at: datetime) -> None:
        with self.connect() as connection:
            connection.execute(
                """
                INSERT INTO sessions(token_hash, expires_at, created_at)
                VALUES (?, ?, ?)
                """,
                (
                    hashlib.sha256(token.encode()).hexdigest(),
                    expires_at.isoformat(),
                    datetime.now(UTC).isoformat(),
                ),
            )

    def session_expiry(self, token: str) -> datetime | None:
        token_hash = hashlib.sha256(token.encode()).hexdigest()
        with self.connect() as connection:
            row = connection.execute(
                "SELECT expires_at FROM sessions WHERE token_hash = ?",
                (token_hash,),
            ).fetchone()
        if row is None:
            return None
        expires_at = datetime.fromisoformat(row["expires_at"])
        if expires_at <= datetime.now(UTC):
            self.revoke_session(token)
            return None
        return expires_at

    def revoke_session(self, token: str) -> None:
        with self.connect() as connection:
            connection.execute(
                "DELETE FROM sessions WHERE token_hash = ?",
                (hashlib.sha256(token.encode()).hexdigest(),),
            )

    def prices(self) -> dict[str, dict[str, object]]:
        with self.connect() as connection:
            rows = connection.execute(
                "SELECT symbol, idr_per_unit, source, fetched_at FROM price_snapshots"
            ).fetchall()
        return {
            row["symbol"]: {
                "idrPerUnit": row["idr_per_unit"],
                "source": row["source"],
                "fetchedAt": row["fetched_at"],
            }
            for row in rows
        }

    def upsert_prices(self, prices: dict[str, float], source: str) -> None:
        fetched_at = datetime.now(UTC).isoformat()
        with self.connect() as connection:
            connection.executemany(
                """
                INSERT INTO price_snapshots(symbol, idr_per_unit, source, fetched_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(symbol) DO UPDATE SET
                    idr_per_unit = excluded.idr_per_unit,
                    source = excluded.source,
                    fetched_at = excluded.fetched_at
                """,
                [(symbol, price, source, fetched_at) for symbol, price in prices.items()],
            )

    def historical_prices(self, rate_date: str) -> dict[str, float]:
        with self.connect() as connection:
            rows = connection.execute(
                """
                SELECT symbol, idr_per_unit FROM historical_price_snapshots
                WHERE date = ?
                """,
                (rate_date,),
            ).fetchall()
        return {row["symbol"]: float(row["idr_per_unit"]) for row in rows}

    def save_historical_prices(
        self, rate_date: str, prices: dict[str, float], source: str
    ) -> None:
        fetched_at = datetime.now(UTC).isoformat()
        with self.connect() as connection:
            connection.executemany(
                """
                INSERT OR IGNORE INTO historical_price_snapshots(
                    date, symbol, idr_per_unit, source, fetched_at
                ) VALUES (?, ?, ?, ?, ?)
                """,
                [
                    (rate_date, symbol, price, source, fetched_at)
                    for symbol, price in prices.items()
                ],
            )

    def price(self, asset: str) -> float:
        if asset == "idr":
            return 1.0
        with self.connect() as connection:
            row = connection.execute(
                "SELECT idr_per_unit FROM price_snapshots WHERE symbol = ?", (asset,)
            ).fetchone()
        if row is None:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail=f"No cached price is available for {asset}",
            )
        return float(row["idr_per_unit"])

    @staticmethod
    def entry_dict(row: sqlite3.Row) -> dict[str, object]:
        return {
            "id": row["id"],
            "asset": row["asset"],
            "amount": row["amount"],
            "source": row["source"],
            "date": row["date"],
            "costBasisIdr": row["cost_basis_idr"],
            "kind": row["kind"],
            "createdAt": row["created_at"],
        }

    @staticmethod
    def conversion_dict(row: sqlite3.Row) -> dict[str, object]:
        return {
            "id": row["id"],
            "fromAsset": row["from_asset"],
            "fromAmount": row["from_amount"],
            "toAsset": row["to_asset"],
            "toAmount": row["to_amount"],
            "sourceValueIdr": row["source_value_idr"],
            "targetValueIdr": row["target_value_idr"],
            "costBasisIdr": row["cost_basis_idr"],
            "realizedProfitIdr": row["realized_profit_idr"],
            "date": row["date"],
            "createdAt": row["created_at"],
        }


def create_app(
    database_path: Path | str | None = None,
    price_provider: PriceProvider | None = None,
) -> FastAPI:
    db = Database(
        Path(database_path or os.environ.get("PIGGYLOG_DATABASE", "piggylog.db"))
    )
    provider = price_provider or LivePriceProvider()

    async def refresh_prices() -> dict[str, dict[str, object]]:
        failures: list[str] = []
        try:
            exchange_prices = await provider.fetch_exchange_rates("latest")
            if any(
                not math.isfinite(price) or price <= 0
                for price in exchange_prices.values()
            ):
                raise ValueError("Exchange-rate provider returned a non-positive price")
            db.upsert_prices(exchange_prices, "exchange-api")
        except Exception as error:
            failures.append(f"currencies: {error}")
            logger.warning("Currency price refresh failed: %s", error)

        try:
            gold_usd_per_gram = await provider.fetch_gold_usd_per_gram()
            if gold_usd_per_gram <= 0:
                raise ValueError("Gold-price provider returned a non-positive price")
            usd_idr = db.price("usd")
            db.upsert_prices({"gold": gold_usd_per_gram * usd_idr}, "api.gold-api.com")
        except Exception as error:
            failures.append(f"gold: {error}")
            logger.warning("Gold price refresh failed: %s", error)

        prices = db.prices()
        if failures and not prices:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail={"message": "Price refresh failed", "errors": failures},
            )
        if failures:
            logger.warning("Price refresh was partial: %s", "; ".join(failures))
        return prices

    async def historical_unit_price(asset: str, rate_date: str) -> float:
        if asset == "idr":
            db.save_historical_prices(rate_date, {"idr": 1.0}, "fixed")
            return db.historical_prices(rate_date)["idr"]

        snapshots = db.historical_prices(rate_date)
        required_symbol = "usd" if asset == "gold" else asset
        if required_symbol not in snapshots:
            try:
                exchange_prices = await provider.fetch_exchange_rates(rate_date)
            except ValueError as error:
                logger.error(
                    "Could not load historical exchange rates for %s: %s",
                    rate_date,
                    error,
                )
                raise HTTPException(
                    status_code=status.HTTP_502_BAD_GATEWAY,
                    detail=f"Historical exchange rates are unavailable for {rate_date}",
                ) from error
            if any(
                not math.isfinite(price) or price <= 0
                for price in exchange_prices.values()
            ):
                raise HTTPException(
                    status_code=status.HTTP_502_BAD_GATEWAY,
                    detail=f"Historical exchange rates are invalid for {rate_date}",
                )
            db.save_historical_prices(rate_date, exchange_prices, "exchange-api")
            snapshots = db.historical_prices(rate_date)

        if required_symbol not in snapshots:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=f"Historical {asset.upper()} exchange rate is unavailable for {rate_date}",
            )
        if asset != "gold":
            return snapshots[asset]
        if "gold" in snapshots:
            return snapshots["gold"]

        # Keep the existing gold quote source and apply the historical USD/IDR rate.
        gold_usd_per_gram = db.price("gold") / db.price("usd")
        historical_gold_idr = gold_usd_per_gram * snapshots["usd"]
        db.save_historical_prices(
            rate_date,
            {"gold": historical_gold_idr},
            "api.gold-api.com + exchange-api",
        )
        return db.historical_prices(rate_date)["gold"]

    async def scheduled_price_refresh() -> None:
        while True:
            try:
                await refresh_prices()
            except Exception:
                logger.exception("Scheduled price refresh failed")
            await asyncio.sleep(PRICE_REFRESH_INTERVAL_SECONDS)

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        db.initialize()
        refresh_task = asyncio.create_task(scheduled_price_refresh())
        try:
            yield
        finally:
            refresh_task.cancel()
            try:
                await refresh_task
            except asyncio.CancelledError:
                pass

    app = FastAPI(title="PiggyLog API", version="1.0.0", lifespan=lifespan)
    app.state.database = db
    app.state.price_provider = provider
    bearer = HTTPBearer(auto_error=False)

    def require_session(
        credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    ) -> tuple[str, datetime]:
        if credentials is None or credentials.scheme.lower() != "bearer":
            raise HTTPException(
                status_code=401,
                detail="Authentication required",
                headers={"WWW-Authenticate": "Bearer"},
            )
        expires_at = db.session_expiry(credentials.credentials)
        if expires_at is None:
            raise HTTPException(
                status_code=401,
                detail="Session is invalid or expired",
                headers={"WWW-Authenticate": "Bearer"},
            )
        return credentials.credentials, expires_at

    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["GET", "POST", "DELETE"],
        allow_headers=["*"],
    )

    @app.get("/")
    def root() -> dict[str, str]:
        return {"service": "PiggyLog API", "health": "/health"}

    @app.get("/health")
    def health() -> dict[str, bool]:
        return {"ok": True}

    @app.post("/auth/login")
    def login(payload: LoginRequest) -> dict[str, str]:
        configured_username = os.environ.get("PIGGYLOG_USERNAME")
        configured_password = os.environ.get("PIGGYLOG_PASSWORD")
        if not configured_username or not configured_password:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Server login credentials are not configured",
            )
        username_matches = secrets.compare_digest(
            payload.username.encode(), configured_username.encode()
        )
        password_matches = secrets.compare_digest(
            payload.password.encode(), configured_password.encode()
        )
        if not username_matches or not password_matches:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid username or password",
                headers={"WWW-Authenticate": "Bearer"},
            )

        token = secrets.token_urlsafe(32)
        expires_at = datetime.now(UTC) + timedelta(days=30)
        db.create_session(token, expires_at)
        return {
            "access_token": token,
            "token_type": "bearer",
            "expires_at": expires_at.isoformat(),
        }

    @app.get("/auth/session")
    def get_session(
        session: tuple[str, datetime] = Depends(require_session),
    ) -> dict[str, object]:
        return {"ok": True, "expiresAt": session[1].isoformat()}

    @app.delete("/auth/session", status_code=status.HTTP_204_NO_CONTENT)
    def delete_session(
        session: tuple[str, datetime] = Depends(require_session),
    ) -> Response:
        db.revoke_session(session[0])
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    @app.get("/api/v1/prices")
    def get_prices(
        _: tuple[str, datetime] = Depends(require_session),
    ) -> dict[str, object]:
        return {"prices": db.prices()}

    @app.post("/api/v1/prices/refresh")
    async def post_prices_refresh(
        _: tuple[str, datetime] = Depends(require_session),
    ) -> dict[str, object]:
        return {"prices": await refresh_prices()}

    @app.get("/api/v1/entries")
    def get_entries(
        _: tuple[str, datetime] = Depends(require_session),
    ) -> list[dict[str, object]]:
        with db.connect() as connection:
            rows = connection.execute(
                """
                SELECT id, asset, amount, source, date, cost_basis_idr, kind, created_at
                FROM entries ORDER BY date DESC, id DESC
                """
            ).fetchall()
        return [db.entry_dict(row) for row in rows]

    @app.post("/api/v1/entries", status_code=status.HTTP_201_CREATED)
    async def create_entry(
        entry: EntryCreate,
        _: tuple[str, datetime] = Depends(require_session),
    ) -> dict[str, object]:
        if entry.cost_basis_idr is not None:
            cost_basis = entry.cost_basis_idr
        else:
            rate_date = entry.date.date().isoformat()
            if rate_date == datetime.now(UTC).date().isoformat():
                unit_price = db.price(entry.asset)
            else:
                unit_price = await historical_unit_price(entry.asset, rate_date)
            cost_basis = entry.amount * unit_price
        created_at = datetime.now(UTC).isoformat()
        with db.connect() as connection:
            cursor = connection.execute(
                """
                INSERT INTO entries(asset, amount, source, date, cost_basis_idr, kind, created_at)
                VALUES (?, ?, ?, ?, ?, 'saving', ?)
                """,
                (
                    entry.asset,
                    entry.amount,
                    entry.source.strip(),
                    entry.date.isoformat(),
                    cost_basis,
                    created_at,
                ),
            )
            row = connection.execute(
                """
                SELECT id, asset, amount, source, date, cost_basis_idr, kind, created_at
                FROM entries WHERE id = ?
                """,
                (cursor.lastrowid,),
            ).fetchone()
        return db.entry_dict(row)

    @app.delete("/api/v1/entries/{entry_id}", status_code=status.HTTP_204_NO_CONTENT)
    def delete_entry(
        entry_id: int,
        _: tuple[str, datetime] = Depends(require_session),
    ) -> Response:
        with db.connect() as connection:
            entry = connection.execute(
                "SELECT asset, amount, kind FROM entries WHERE id = ?", (entry_id,)
            ).fetchone()
            if entry is None:
                raise HTTPException(status_code=404, detail="Entry not found")
            if entry["kind"] != "saving":
                raise HTTPException(
                    status_code=409, detail="Conversion entries cannot be deleted directly"
                )
            holding = connection.execute(
                "SELECT COALESCE(SUM(amount), 0) AS amount FROM entries WHERE asset = ?",
                (entry["asset"],),
            ).fetchone()["amount"]
            if float(holding) + 1e-9 < float(entry["amount"]):
                raise HTTPException(
                    status_code=409,
                    detail="This saving has already been partially or fully converted",
                )
            connection.execute("DELETE FROM entries WHERE id = ?", (entry_id,))
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    @app.get("/api/v1/conversions")
    def get_conversions(
        _: tuple[str, datetime] = Depends(require_session),
    ) -> list[dict[str, object]]:
        with db.connect() as connection:
            rows = connection.execute(
                """
                SELECT id, from_asset, from_amount, to_asset, to_amount,
                       source_value_idr, target_value_idr, cost_basis_idr,
                       realized_profit_idr, date, created_at
                FROM conversions ORDER BY date DESC, id DESC
                """
            ).fetchall()
        return [db.conversion_dict(row) for row in rows]

    @app.post("/api/v1/conversions", status_code=status.HTTP_201_CREATED)
    def create_conversion(
        conversion: ConversionCreate,
        _: tuple[str, datetime] = Depends(require_session),
    ) -> dict[str, object]:
        source_price = db.price(conversion.from_asset)
        target_price = db.price(conversion.to_asset)
        source_value = conversion.amount * source_price
        target_amount = source_value / target_price
        target_value = target_amount * target_price
        created_at = datetime.now(UTC).isoformat()

        with db.connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            holding = connection.execute(
                """
                SELECT COALESCE(SUM(amount), 0) AS amount,
                       COALESCE(SUM(cost_basis_idr), 0) AS cost_basis
                FROM entries WHERE asset = ?
                """,
                (conversion.from_asset,),
            ).fetchone()
            source_holding = float(holding["amount"])
            if source_holding + 1e-9 < conversion.amount:
                raise HTTPException(
                    status_code=409, detail="Insufficient balance for this conversion"
                )

            source_cost_basis = (
                float(holding["cost_basis"]) / source_holding * conversion.amount
            )
            realized_profit = source_value - source_cost_basis
            conversion_cursor = connection.execute(
                """
                INSERT INTO conversions(
                    from_asset, from_amount, to_asset, to_amount,
                    source_value_idr, target_value_idr, cost_basis_idr,
                    realized_profit_idr, date, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    conversion.from_asset,
                    conversion.amount,
                    conversion.to_asset,
                    target_amount,
                    source_value,
                    target_value,
                    source_cost_basis,
                    realized_profit,
                    conversion.date.isoformat(),
                    created_at,
                ),
            )
            conversion_id = conversion_cursor.lastrowid
            connection.executemany(
                """
                INSERT INTO entries(asset, amount, source, date, cost_basis_idr, kind, created_at)
                VALUES (?, ?, 'Conversion', ?, ?, 'conversion', ?)
                """,
                [
                    (
                        conversion.from_asset,
                        -conversion.amount,
                        conversion.date.isoformat(),
                        -source_cost_basis,
                        created_at,
                    ),
                    (
                        conversion.to_asset,
                        target_amount,
                        conversion.date.isoformat(),
                        target_value,
                        created_at,
                    ),
                ],
            )
            row = connection.execute(
                """
                SELECT id, from_asset, from_amount, to_asset, to_amount,
                       source_value_idr, target_value_idr, cost_basis_idr,
                       realized_profit_idr, date, created_at
                FROM conversions WHERE id = ?
                """,
                (conversion_id,),
            ).fetchone()
        return db.conversion_dict(row)

    @app.get("/api/v1/summary")
    def get_summary(
        _: tuple[str, datetime] = Depends(require_session),
    ) -> dict[str, object]:
        with db.connect() as connection:
            entries = connection.execute(
                "SELECT asset, amount, cost_basis_idr FROM entries"
            ).fetchall()
            realized = connection.execute(
                "SELECT COALESCE(SUM(realized_profit_idr), 0) AS total FROM conversions"
            ).fetchone()["total"]
            invested = connection.execute(
                """
                SELECT COALESCE(SUM(cost_basis_idr), 0) AS total
                FROM entries WHERE kind = 'saving'
                """
            ).fetchone()["total"]

        holdings: dict[str, float] = {}
        cost_basis = 0.0
        current_value = 0.0
        for entry in entries:
            asset = entry["asset"]
            amount = float(entry["amount"])
            holdings[asset] = holdings.get(asset, 0.0) + amount
            cost_basis += float(entry["cost_basis_idr"])
            current_value += amount * db.price(asset)
        holdings = {asset: amount for asset, amount in holdings.items() if abs(amount) > 1e-9}

        unrealized_profit = current_value - cost_basis
        total_profit = unrealized_profit + float(realized)
        invested = float(invested)
        profit_percent = total_profit / invested * 100 if invested else 0.0
        return {
            "totalIdr": current_value,
            "costBasisIdr": cost_basis,
            "investedIdr": invested,
            "unrealizedProfitIdr": unrealized_profit,
            "realizedProfitIdr": realized,
            "profitIdr": total_profit,
            "profitPercent": profit_percent,
            "holdings": holdings,
            "prices": db.prices(),
        }

    return app


app = create_app()
