# customer-order-cancellation

## User outcome

A customer can request cancellation of a paid order from the order details page.
The page confirms the request without hiding the receipt, item, or shipment information.

## Repositories

- `api`: `__EXAMPLE_WORKSPACE__/acme-orders-api`
- `web`: `__EXAMPLE_WORKSPACE__/acme-storefront`

## Shared contract

The storefront sends `POST /v1/orders/:id/cancellation` with `Content-Type: application/json`.
The JSON body must contain a `reason` with one of these values: `ordered_by_mistake`, `found_better_price`, or `other`.

A successful request returns HTTP `200` and the complete updated order representation.
The updated order has `status` set to `cancellation_requested` and contains `cancellation: { "reason": "<submitted reason>" }`.
A later `GET /v1/orders/:id` returns the same cancellation state while the API process continues to run.

The API returns these errors as JSON:

| Condition | Status | Body |
|---|---:|---|
| The order does not exist. | `404` | `{ "error": "order_not_found" }` |
| The JSON body is malformed, is not an object, has no reason, or has an unsupported reason. | `400` | `{ "error": "invalid_cancellation_reason" }` |
| The order already has a cancellation request. | `409` | `{ "error": "cancellation_already_requested" }` |
| The order does not have `paid` status. | `409` | `{ "error": "order_not_cancellable" }` |

The API checks for an existing cancellation request before it checks whether the order is otherwise eligible.
All API responses for this endpoint include `Access-Control-Allow-Origin: http://localhost:3000`.
The API answers the browser preflight request with HTTP `204` and permits `POST`, `OPTIONS`, and the `Content-Type` request header.

## State transitions and invariants

A successful request changes an order from `paid` to `cancellation_requested` exactly once.
The API does not change the order when it returns an error.
The stored cancellation reason is one of the three allowed values.
An order with `cancellation_requested` status has a cancellation object with its submitted reason.
The API keeps cancellation requests in memory, so restarting the API restores the initial order data and removes submitted requests.

The storefront permits only one cancellation request at a time.
It disables the cancellation controls while the request is running.
After success, it renders the order returned by the API and replaces the form with a confirmation that includes the selected reason.
After failure, it keeps the current order details and cancellation controls visible, shows an accessible error, and permits another attempt.

## Authorization

The current application has no customer authentication or authorization model.
The cancellation endpoint is therefore unauthenticated, like the existing order endpoints.
Adding authentication or ownership checks is outside this feature.

## Feature scenarios

### Request cancellation of a paid order

Given `order-1001` has `paid` status.
When the customer selects `ordered_by_mistake` and submits the request.
Then the API returns HTTP `200`.
And the order status becomes `cancellation_requested`.
And the storefront shows the cancellation reason.

### Submit the same request twice

Given `order-1001` already has a cancellation request.
When the customer submits another cancellation request.
Then the API returns HTTP `409` with `cancellation_already_requested`.
And the existing cancellation request does not change.

### Submit an invalid reason

Given `order-1001` has `paid` status.
When the customer submits a missing or unsupported reason.
Then the API returns HTTP `400` with `invalid_cancellation_reason`.
And the order does not change.

### Request cancellation for an unknown order

When the customer requests cancellation of an unknown order.
Then the API returns HTTP `404` with `order_not_found`.

### Request cancellation of an ineligible order

Given an order does not have `paid` status and has no existing cancellation request.
When the customer requests cancellation.
Then the API returns HTTP `409` with `order_not_cancellable`.
And the order does not change.

### Recover from a storefront request failure

Given the storefront displays a paid order.
When the cancellation request fails.
Then the storefront keeps the order details and cancellation controls visible.
And it shows an accessible error.
And the customer can try again.

## Completion rules

All required repositories must complete their acceptance criteria and focused tests.
RepoChord creates local commits after successful repository-agent verification.
Repository agents must not stage, commit, push, or merge changes.
