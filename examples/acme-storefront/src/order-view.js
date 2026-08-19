function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

export function formatOrderStatus(status) {
  return status.replaceAll("_", " ").replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function formatMoney(amountCents, currency) {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency
  }).format(amountCents / 100);
}

function formatDeliveryDate(date) {
  const deliveryDate = new Date(`${date}T00:00:00Z`);

  if (Number.isNaN(deliveryDate.getTime())) {
    return date;
  }

  return new Intl.DateTimeFormat("en-US", {
    dateStyle: "long",
    timeZone: "UTC"
  }).format(deliveryDate);
}

function formatEventTime(timestamp) {
  const eventTime = new Date(timestamp);

  if (Number.isNaN(eventTime.getTime())) {
    return timestamp;
  }

  return new Intl.DateTimeFormat("en-US", {
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
    month: "short",
    timeZone: "UTC",
    timeZoneName: "short",
    year: "numeric"
  }).format(eventTime);
}

function createReceiptUrl(orderId) {
  const encodedOrderId = encodeURIComponent(String(orderId));

  return `http://localhost:3001/v1/orders/${encodedOrderId}/receipt`;
}

function renderOrderItem(item, currency) {
  const formattedUnitPrice = formatMoney(item.unitPriceCents, currency);
  const formattedSubtotal = formatMoney(item.lineSubtotalCents, currency);

  return `
    <tr>
      <td>${escapeHtml(item.productName)}</td>
      <td>${escapeHtml(item.sku)}</td>
      <td>${escapeHtml(item.quantity)}</td>
      <td>${escapeHtml(formattedUnitPrice)}</td>
      <td>${escapeHtml(formattedSubtotal)}</td>
    </tr>
  `;
}

function renderTrackingEvent(event) {
  return `
    <li class="tracking-event">
      <p class="tracking-event-status">${escapeHtml(formatOrderStatus(event.status))}</p>
      <p class="tracking-event-description">${escapeHtml(event.description)}</p>
      <p class="tracking-event-meta">
        <span>${escapeHtml(event.location)}</span>
        <time datetime="${escapeHtml(event.occurredAt)}">${escapeHtml(formatEventTime(event.occurredAt))}</time>
      </p>
    </li>
  `;
}

function renderShipment(shipment) {
  const formattedDeliveryDate = formatDeliveryDate(shipment.estimatedDeliveryDate);
  const trackingEvents = shipment.events.map((event) => renderTrackingEvent(event)).join("");

  return `
    <section class="shipment" aria-labelledby="shipment-heading">
      <h3 id="shipment-heading">Shipment</h3>
      <dl class="shipment-summary">
        <dt>Carrier</dt>
        <dd>${escapeHtml(shipment.carrier)}</dd>
        <dt>Tracking number</dt>
        <dd>${escapeHtml(shipment.trackingNumber)}</dd>
        <dt>Estimated delivery</dt>
        <dd><time datetime="${escapeHtml(shipment.estimatedDeliveryDate)}">${escapeHtml(formattedDeliveryDate)}</time></dd>
      </dl>
      <h4 id="tracking-timeline-heading">Tracking timeline</h4>
      <ol class="tracking-timeline" aria-labelledby="tracking-timeline-heading">${trackingEvents}</ol>
    </section>
  `;
}

export function renderOrder(order) {
  const formattedTotal = formatMoney(order.totalCents, order.currency);
  const itemRows = order.items.map((item) => renderOrderItem(item, order.currency)).join("");
  const receiptUrl = createReceiptUrl(order.id);
  const shipment = order.shipment ? renderShipment(order.shipment) : "";

  return `
    <article class="order-card" data-order-id="${escapeHtml(order.id)}">
      <h2>${escapeHtml(order.id)}</h2>
      <dl>
        <dt>Status</dt>
        <dd data-order-status>${escapeHtml(formatOrderStatus(order.status))}</dd>
        <dt>Total</dt>
        <dd>${escapeHtml(formattedTotal)}</dd>
      </dl>
      <a href="${escapeHtml(receiptUrl)}">Download receipt</a>
      ${shipment}
      <section class="order-items" aria-labelledby="order-items-heading">
        <h3 id="order-items-heading">Items</h3>
        <div class="order-items-table-container">
          <table>
            <thead>
              <tr>
                <th scope="col">Product</th>
                <th scope="col">SKU</th>
                <th scope="col">Quantity</th>
                <th scope="col">Unit price</th>
                <th scope="col">Subtotal</th>
              </tr>
            </thead>
            <tbody>${itemRows}</tbody>
          </table>
        </div>
      </section>
    </article>
  `;
}
