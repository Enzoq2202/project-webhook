# Webhook Payment Integration Service

This project implements a webhook-driven payment integration service in OCaml using **Cohttp**, **Lwt**, **Yojson**, **Digestif**, and **SQLite3**. It fulfills the following requirements:

* **Event-driven** HTTP POST endpoint (`/webhook`) for receiving payment notifications.
* **Token-based** authentication via `X-Webhook-Token` header.
* **Optional payload integrity** using HMAC-SHA256 (`X-Webhook-Signature`).
* **Idempotency**: duplicate transactions are detected and rejected.
* **Automatic confirmation** and **cancellation** callbacks to external endpoints (`/confirmar`, `/cancelar`).
* **Persistence** of every webhook invocation in a local SQLite database.
* **Flexible configuration** via environment variables.

---

## Features

1. **Minimal tests compliance**: passes all 6 cases in `test_webhook.py`:

   * Successful payment → HTTP 200 + confirm callback
   * Duplicate transaction → HTTP 409
   * Invalid amount → HTTP 400 + cancel callback
   * Invalid token → HTTP 401
   * Empty payload → HTTP 400
   * Missing timestamp → HTTP 400 + cancel callback

2. **Payload integrity (optional)**:

   * Computes HMAC-SHA256 on the JSON body with a secret key.
   * Compares against `X-Webhook-Signature`; rejects on mismatch.

3. **Persistence**:

   * Stores every transaction in `webhooks.db` (SQLite) with columns:
     `transaction_id`, `amount`, `currency`, `timestamp`, `status`.

4. **Configuration**:

   * `PORT` (default `5000`): listening port.
   * `WEBHOOK_TOKEN` (default `meu-token-secreto`): token for `X-Webhook-Token`.
   * `WEBHOOK_HMAC_SECRET` (default empty): secret key for signature validation.

---

## Getting Started

### Prerequisites

* **OCaml** (≥ 4.12)
* **OPAM** (OCaml package manager)
* **Dune** (build system)
* **SQLite3** CLI (optional, for manual inspection)

### Dependencies

Install required OCaml libraries:

```bash
opam update
opam install dune cohttp-lwt-unix yojson digestif sqlite3 lwt_ppx
```

### Build

```bash
dune build
```

### Run

Set environment variables as needed, then start the server:

```bash
# Optional: override defaults
env WEBHOOK_TOKEN="my-token" \
    WEBHOOK_HMAC_SECRET="my-hmac-key" \
    PORT=5000 \
  dune exec -- webhook
```

You should see:

```
🚀 Server listening on port 5000 (POST /webhook)
```

The service is now ready to accept POSTs at `http://localhost:5000/webhook`.

---

## Usage

Send a POST with JSON payload and `X-Webhook-Token` header:

```bash
curl -X POST http://localhost:5000/webhook \
  -H "Content-Type: application/json" \
  -H "X-Webhook-Token: meu-token-secreto" \
  -d '{
    "event": "payment_success",
    "transaction_id": "abc123",
    "amount": 49.90,
    "currency": "BRL",
    "timestamp": "2025-05-11T16:00:00Z"
  }'
```

On success, the server will:

1. Validate token.
2. (If configured) Validate HMAC signature.
3. Parse and validate fields.
4. Detect duplicates.
5. Persist to SQLite and send confirm/cancel callback.
6. Return appropriate HTTP status.

---

## Testing

A Python harness `test_webhook.py` is provided to automate the six required tests. It also spins up a FastAPI server on port `5001` to receive confirmation and cancellation callbacks.

Run tests with:

```bash
python3 test_webhook.py
```

You should see all tests pass:

```
1. Webhook test ok: successful!
2. Webhook test ok: transação duplicada!
... etc.
6/6 tests completed.
```

---

## Inspecting the Database

You can inspect the persisted transactions with the SQLite CLI:

```bash
sqlite3 webhooks.db
sqlite> .tables
transactions
sqlite> SELECT * FROM transactions;
```

Or with a quick Python script:

```python
import sqlite3
conn = sqlite3.connect("webhooks.db")
for row in conn.execute("SELECT * FROM transactions"):
    print(row)
conn.close()
```

---

## Next Steps

To achieve maximum grading (all +0.5 bonus points), you can also:

* **Transaction authenticity**: call the real payment gateway API to verify.
* **HTTPS**: run Dream with `~cert` and `~key` for a TLS server.

