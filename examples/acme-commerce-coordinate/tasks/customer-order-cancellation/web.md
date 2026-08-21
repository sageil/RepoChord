# customer-order-cancellation task for web

## Repository

Repository key: `web`

Repository path: `__EXAMPLE_WORKSPACE__/acme-storefront`

## Goal

Let a customer submit and review an order cancellation request from the order details page.

## Shared contract

For an order with `paid` status and no cancellation request, show a reason selector and a `Request cancellation` button.
The selector offers `Ordered by mistake`, `Found a better price`, and `Other` with values `ordered_by_mistake`, `found_better_price`, and `other`.

Submit `POST http://localhost:3001/v1/orders/:id/cancellation` with `Content-Type: application/json` and `{ "reason": "<selected value>" }`.
Encode the order ID as one URL path segment.
A successful response is the complete updated order with `status: "cancellation_requested"` and `cancellation: { "reason": "<submitted reason>" }`.

While the request is running, prevent a second submission and disable the cancellation controls.
After success, render the returned order and replace the controls with a confirmation that shows a human-readable cancellation reason.
When an order already contains a cancellation request, show the confirmation without showing the request form.
When the API request fails, keep the current order details and cancellation controls visible, show an accessible error, and permit another attempt.
Do not hide or remove the existing receipt, item, or shipment information.

The API can return `order_not_found`, `invalid_cancellation_reason`, `cancellation_already_requested`, or `order_not_cancellable`.
The storefront must show a clear customer-facing error for a non-success response and for a network failure.

## Acceptance criteria

- A paid order shows the three cancellation reasons and the request button.
- Submitting the form sends the documented method, URL, header, and JSON body.
- Cancellation controls are disabled while the request is running.
- A successful response updates the rendered status and shows the selected reason in human-readable form.
- An order with an existing cancellation request shows its reason and does not show the form.
- A non-paid order without a cancellation request does not show the form.
- API and network failures keep the order content visible, show an accessible error, and allow a retry.
- Dynamic order, cancellation, and error values are safely rendered.
- Existing receipt, item, and shipment displays continue to work.
- Automated tests cover rendering, request construction, success, duplicate submission prevention, and failure recovery.

## Required verification

`npm test`

## Commit

RepoChord creates the commit only after all acceptance criteria and required tests pass.

Commit message: `feat(web): add order cancellation requests`

Do not stage, commit, push, merge, or rebase.
