import asyncio

import httpx
from fastapi.testclient import TestClient
import pytest

from main import LivePriceProvider, create_app


class StubPriceProvider:
    def __init__(self):
        self.exchange_rate_calls = []
        self.historical_rates = {"idr": 1.0, "usd": 15_000.0, "sar": 4_000.0}

    async def fetch_exchange_rates(self, rate_date: str = "latest") -> dict[str, float]:
        self.exchange_rate_calls.append(rate_date)
        if rate_date == "latest":
            return {"idr": 1.0, "usd": 16_000.0, "sar": 4_200.0}
        return self.historical_rates

    async def fetch_gold_usd_per_gram(self) -> float:
        return 100.0


class FailingHistoricalPriceProvider(StubPriceProvider):
    async def fetch_exchange_rates(self, rate_date: str = "latest") -> dict[str, float]:
        if rate_date == "latest":
            return await super().fetch_exchange_rates(rate_date)
        self.exchange_rate_calls.append(rate_date)
        raise ValueError("Both historical exchange-api URLs failed")


def make_client(tmp_path, monkeypatch, price_provider=None):
    monkeypatch.setenv("PIGGYLOG_USERNAME", "alice")
    monkeypatch.setenv("PIGGYLOG_PASSWORD", "correct-horse")
    app = create_app(
        database_path=tmp_path / "test.db",
        price_provider=price_provider or StubPriceProvider(),
    )
    return TestClient(app)


def authenticate(client):
    response = client.post(
        "/auth/login",
        json={"username": "alice", "password": "correct-horse"},
    )
    assert response.status_code == 200
    client.headers.update(
        {"Authorization": f"Bearer {response.json()['access_token']}"}
    )


def test_conversion_realizes_profit_and_preserves_total_profit(tmp_path, monkeypatch):
    with make_client(tmp_path, monkeypatch) as client:
        authenticate(client)
        assert client.post("/api/v1/prices/refresh").status_code == 200
        saving = client.post(
            "/api/v1/entries",
            json={
                "asset": "usd",
                "amount": 10,
                "cost_basis_idr": 150_000,
                "date": "2026-01-01T00:00:00Z",
            },
        )
        assert saving.status_code == 201

        before = client.get("/api/v1/summary").json()
        conversion = client.post(
            "/api/v1/conversions",
            json={"from_asset": "usd", "to_asset": "sar", "amount": 5},
        )
        assert conversion.status_code == 201
        result = conversion.json()
        after = client.get("/api/v1/summary").json()

        assert result["toAmount"] == pytest.approx(80_000 / 4_200)
        assert result["realizedProfitIdr"] == 5_000
        assert before["profitIdr"] == after["profitIdr"] == 10_000
        assert after["realizedProfitIdr"] == 5_000
        assert after["unrealizedProfitIdr"] == 5_000
        assert after["profitPercent"] == pytest.approx(100 / 15)


def test_conversion_rejects_insufficient_balance_without_writing(tmp_path, monkeypatch):
    with make_client(tmp_path, monkeypatch) as client:
        authenticate(client)
        client.post("/api/v1/prices/refresh")
        response = client.post(
            "/api/v1/conversions",
            json={"from_asset": "usd", "to_asset": "sar", "amount": 1},
        )
        assert response.status_code == 409
        assert client.get("/api/v1/conversions").json() == []
        assert client.get("/api/v1/entries").json() == []


def test_conversion_rejects_same_asset(tmp_path, monkeypatch):
    with make_client(tmp_path, monkeypatch) as client:
        authenticate(client)
        response = client.post(
            "/api/v1/conversions",
            json={"from_asset": "usd", "to_asset": "usd", "amount": 1},
        )
        assert response.status_code == 422


def test_login_requires_credentials_and_session_can_be_revoked(tmp_path, monkeypatch):
    with make_client(tmp_path, monkeypatch) as client:
        assert client.get("/").json() == {
            "service": "PiggyLog API",
            "health": "/health",
        }
        assert client.get("/health").status_code == 200
        assert client.get("/api/v1/summary").status_code == 401
        assert client.post(
            "/auth/login",
            json={"username": "alice", "password": "incorrect"},
        ).status_code == 401

        authenticate(client)
        assert client.get("/auth/session").status_code == 200
        assert client.get("/api/v1/summary").status_code == 200
        assert client.delete("/auth/session").status_code == 204
        assert client.get("/auth/session").status_code == 401


def test_registration_creates_a_user_session_and_supports_login(
    tmp_path, monkeypatch
):
    with make_client(tmp_path, monkeypatch) as client:
        registration = client.post(
            "/auth/register",
            json={"username": "new-user", "password": "secure-password"},
        )
        assert registration.status_code == 201
        token = registration.json()["access_token"]
        client.headers.update({"Authorization": f"Bearer {token}"})
        assert client.get("/auth/session").status_code == 200

        assert client.post(
            "/auth/login",
            json={"username": "new-user", "password": "incorrect-password"},
        ).status_code == 401
        login = client.post(
            "/auth/login",
            json={"username": "new-user", "password": "secure-password"},
        )
        assert login.status_code == 200
        assert login.json()["access_token"]

        assert client.post(
            "/auth/register",
            json={"username": "New-User", "password": "another-password"},
        ).status_code == 409
        assert client.post(
            "/auth/register",
            json={"username": "alice", "password": "secure-password"},
        ).status_code == 409


@pytest.mark.parametrize(
    "payload",
    [
        {"username": "ab", "password": "secure-password"},
        {"username": "bad name", "password": "secure-password"},
        {"username": "valid-user", "password": "short"},
    ],
)
def test_registration_validates_username_and_password(
    tmp_path, monkeypatch, payload
):
    with make_client(tmp_path, monkeypatch) as client:
        assert client.post("/auth/register", json=payload).status_code == 422


def test_backdated_saving_uses_immutable_historical_rate_snapshot(
    tmp_path, monkeypatch
):
    provider = StubPriceProvider()
    with make_client(tmp_path, monkeypatch, provider) as client:
        authenticate(client)
        assert client.post("/api/v1/prices/refresh").status_code == 200
        old_date = "2024-05-17"

        first = client.post(
            "/api/v1/entries",
            json={
                "asset": "usd",
                "amount": 2,
                "date": f"{old_date}T12:00:00Z",
            },
        )
        assert first.status_code == 201
        assert first.json()["costBasisIdr"] == 30_000

        provider.historical_rates = {
            "idr": 1.0,
            "usd": 20_000.0,
            "sar": 5_000.0,
        }
        second = client.post(
            "/api/v1/entries",
            json={
                "asset": "usd",
                "amount": 1,
                "date": f"{old_date}T18:00:00Z",
            },
        )
        assert second.status_code == 201
        assert second.json()["costBasisIdr"] == 15_000
        assert provider.exchange_rate_calls.count(old_date) == 1

        summary = client.get("/api/v1/summary").json()
        assert summary["totalIdr"] == 48_000
        assert summary["costBasisIdr"] == 45_000


def test_price_refresh_uses_latest_exchange_rates(tmp_path, monkeypatch):
    provider = StubPriceProvider()
    with make_client(tmp_path, monkeypatch, provider) as client:
        authenticate(client)

        response = client.post("/api/v1/prices/refresh")

        assert response.status_code == 200
        assert "latest" in provider.exchange_rate_calls
        assert response.json()["prices"]["usd"]["idrPerUnit"] == 16_000


def test_backdated_saving_fails_when_both_historical_urls_fail(
    tmp_path, monkeypatch
):
    provider = FailingHistoricalPriceProvider()
    with make_client(tmp_path, monkeypatch, provider) as client:
        authenticate(client)
        assert client.post("/api/v1/prices/refresh").status_code == 200

        response = client.post(
            "/api/v1/entries",
            json={
                "asset": "usd",
                "amount": 1,
                "date": "2024-05-17T12:00:00Z",
            },
        )

        assert response.status_code == 502
        assert client.get("/api/v1/entries").json() == []
        assert [
            rate_date
            for rate_date in provider.exchange_rate_calls
            if rate_date != "latest"
        ] == ["2024-05-17"]


def test_exchange_api_falls_back_to_pages_url_for_requested_date():
    rate_date = "2024-05-17"
    requested_urls = []

    def respond(request):
        requested_urls.append(str(request.url))
        if "cdn.jsdelivr.net" in request.url.host:
            return httpx.Response(503)
        return httpx.Response(
            200,
            json={
                "date": rate_date,
                "idr": {"usd": 1 / 15_000, "sar": 1 / 4_000},
            },
        )

    async def fetch():
        async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
            return await LivePriceProvider(client).fetch_exchange_rates(rate_date)

    rates = asyncio.run(fetch())

    assert requested_urls == [
        f"https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@{rate_date}/v1/currencies/idr.json",
        f"https://{rate_date}.currency-api.pages.dev/v1/currencies/idr.json",
    ]
    assert rates == {"idr": 1.0, "usd": 15_000.0, "sar": 4_000.0}


def test_exchange_api_raises_after_both_urls_fail():
    rate_date = "2024-05-17"
    requested_urls = []

    def respond(request):
        requested_urls.append(str(request.url))
        return httpx.Response(404)

    async def fetch():
        async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
            return await LivePriceProvider(client).fetch_exchange_rates(rate_date)

    with pytest.raises(ValueError, match="both exchange-api URLs"):
        asyncio.run(fetch())

    assert len(requested_urls) == 2
    assert f"@{rate_date}/" in requested_urls[0]
    assert requested_urls[1].startswith(f"https://{rate_date}.currency-api.pages.dev/")
