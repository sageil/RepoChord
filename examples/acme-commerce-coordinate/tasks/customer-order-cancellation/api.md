# customer-order-cancellation task for api

## Repository

Repository key: `api`

Repository path: `__EXAMPLE_WORKSPACE__/acme-orders-api`

## Goal

Add an in-memory API operation that accepts one cancellation request for an eligible order and returns the updated order.

## Shared contract

Add `POST /v1/orders/:id/cancellation` with a JSON body containing `reason`.
The allowed reasons are `ordered_by_mistake`, `found_better_price`, and `other`.
A successful request returns HTTP `200` with the complete order, sets `status` to `cancellation_requested`, and adds `cancellation: { "reason": "<submitted reason>" }`.
A later `GET /v1/orders/:id` returns the updated state while the API process continues to run.

Return the following JSON errors without changing the order:

| Condition | Status | Body |
|---|---:|---|
| The order does not exist. | `404` | `{ "error": "order_not_found" }` |
| The body is malformed JSON, is not an object, has no reason, or has an unsupported reason. | `400` | `{ "error": "invalid_cancellation_reason" }` |
| The order already has a cancellation request. | `409` | `{ "error": "cancellation_already_requested" }` |
| The order does not have `paid` status. | `409` | `{ "error": "order_not_cancellable" }` |

Check for an existing cancellation before checking general eligibility.
Include `Access-Control-Allow-Origin: http://localhost:3000` on every endpoint response.
Answer the browser preflight request with HTTP `204` and headers that permit `POST`, `OPTIONS`, and `Content-Type`.
Cancellation data is intentionally in memory and resets when the API process restarts.
The endpoint is unauthenticated because this application has no authentication model.

## Acceptance criteria

- A valid request changes `order-1001` from `paid` to `cancellation_requested` and returns the submitted reason.
- The updated cancellation state is visible through the existing order `GET` endpoint.
- A duplicate request returns `cancellation_already_requested` and preserves the first reason.
- Missing, unsupported, non-string, and malformed reasons return `invalid_cancellation_reason` without changing the order.
- Unknown orders return `order_not_found`.
- Orders that are not paid and have no cancellation request return `order_not_cancellable`.
- The preflight response permits the storefront cancellation request.
- Existing health, order, receipt, item, shipment, and CORS behavior continues to work.
- Automated tests cover every success, failure, state, and preflight behavior listed above.

## Required verification

`npm test`

## Commit

RepoChord creates the commit only after all acceptance criteria and required tests pass.

Commit message: `feat(api): add order cancellation requests`

Do not stage, commit, push, merge, or rebase.
