# PiggyLog API

This FastAPI service stores savings and conversions in SQLite. It refreshes currency and gold prices when it starts and every 30 minutes. Use `POST /api/v1/prices/refresh` to request an immediate update.

Set `PIGGYLOG_USERNAME` and `PIGGYLOG_PASSWORD` on the server before starting it. The app first checks `GET /health`, then logs in through `POST /auth/login`. Successful logins create a revocable 30-day bearer session. All `/api/v1` routes require that session. The token is stored in the app's secure storage; entry history is cached locally per server URL.

## Run locally

```sh
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
export PIGGYLOG_USERNAME=alice
export PIGGYLOG_PASSWORD='use-a-long-unique-password'
uvicorn main:app --host 127.0.0.1 --port 8080
```

The database path defaults to `piggylog.db` and can be changed with `PIGGYLOG_DATABASE`.

## API

- `GET /api/v1/prices` and `POST /api/v1/prices/refresh`
- `GET|POST /api/v1/entries`; `DELETE /api/v1/entries/{entry_id}`
- `GET|POST /api/v1/conversions`
- `GET /api/v1/summary`
- `GET /health`
- `POST /auth/login`; `GET|DELETE /auth/session`

Conversions transfer the converted amount's cost basis to the acquired asset and separately record realized profit. The summary combines realized and unrealized profit, and calculates percentage return against the cost basis of savings entries. A new saving's cost basis defaults to its value at the latest cached price; clients may provide `cost_basis_idr` to record the actual purchase amount.

The authentication currently uses a single server-configured username and password, so this is not multi-user authentication. Use HTTPS and a strong password before exposing it beyond a trusted local environment. Data is shared by the server's configured account.
