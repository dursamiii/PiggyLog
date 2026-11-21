from fastapi.testclient import TestClient
import pytest

from main import create_app


class TestPriceProvider:
    async def fetch_exchange_rates(self) -> dict[str, float]:
        return {"idr": 1.0, "usd": 16_000.0, "sar": 4_200.0}

    async def fetch_gold_usd_per_gram(self) -> float:
        return 100.0


def make_client(tmp_path, monkeypatch):
    monkeypatch.setenv("PIGGYLOG_USERNAME", "alice")
    monkeypatch.setenv("PIGGYLOG_PASSWORD", "correct-horse")
    app = create_app(
        database_path=tmp_path / "test.db",
        price_provider=TestPriceProvider(),
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
