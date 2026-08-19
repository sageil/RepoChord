import assert from "node:assert/strict";
import test from "node:test";

import { formatOrderStatus, renderOrder } from "../src/order-view.js";

test("formatOrderStatus formats API status values", () => {
  assert.equal(formatOrderStatus("pending_payment"), "Pending Payment");
});

test("renderOrder displays order details", () => {
  const result = renderOrder({
    id: "order-1001",
    status: "paid",
    totalCents: 7499,
    currency: "USD",
    items: []
  });

  assert.match(result, /order-1001/);
  assert.match(result, /Paid/);
  assert.match(result, /\$74\.99/);
  assert.match(result, />Download receipt</);
  assert.match(
    result,
    /href="http:\/\/localhost:3001\/v1\/orders\/order-1001\/receipt"/
  );
});

test("renderOrder URL-encodes and HTML-escapes the receipt order ID", () => {
  const result = renderOrder({
    id: 'unsafe/id?query=<script>"&value=1',
    status: "paid",
    totalCents: 7499,
    currency: "USD",
    items: []
  });

  assert.match(
    result,
    /href="http:\/\/localhost:3001\/v1\/orders\/unsafe%2Fid%3Fquery%3D%3Cscript%3E%22%26value%3D1\/receipt"/
  );
  assert.doesNotMatch(result, /<script>/);
});

test("renderOrder escapes values before adding them to HTML", () => {
  const result = renderOrder({
    id: "<script>alert(1)</script>",
    status: "paid",
    totalCents: 7499,
    currency: "USD",
    items: []
  });

  assert.doesNotMatch(result, /<script>/);
  assert.match(result, /&lt;script&gt;/);
});

test("renderOrder displays a row for each item with all item values and headings", () => {
  const result = renderOrder({
    id: "order-1001",
    status: "paid",
    totalCents: 7499,
    currency: "USD",
    items: [
      {
        productName: "Cedar mug",
        sku: "MUG-CEDAR",
        quantity: 2,
        unitPriceCents: 2500,
        lineSubtotalCents: 5000
      },
      {
        productName: "Notebook",
        sku: "NOTE-A5",
        quantity: 1,
        unitPriceCents: 2499,
        lineSubtotalCents: 2499
      }
    ]
  });

  for (const heading of ["Product", "SKU", "Quantity", "Unit price", "Subtotal"]) {
    assert.match(result, new RegExp(`<th scope="col">${heading}</th>`));
  }

  for (const value of ["Cedar mug", "MUG-CEDAR", "2", "Notebook", "NOTE-A5", "1"]) {
    assert.match(result, new RegExp(`>${value}<`));
  }

  assert.equal((result.match(/<tr>/g) ?? []).length, 3);
  assert.match(result, />\$25\.00</);
  assert.match(result, />\$50\.00</);
  assert.match(result, />\$24\.99</);
});

test("renderOrder uses the order currency for item prices and escapes item text", () => {
  const result = renderOrder({
    id: "order-1002",
    status: "paid",
    totalCents: 1300,
    currency: "EUR",
    items: [
      {
        productName: "<img src=x onerror=alert(1)>",
        sku: "SKU-<unsafe>",
        quantity: 1,
        unitPriceCents: 650,
        lineSubtotalCents: 650
      }
    ]
  });

  assert.match(result, />€6\.50</);
  assert.doesNotMatch(result, /<img src=x onerror=alert\(1\)>/);
  assert.match(result, /&lt;img src=x onerror=alert\(1\)&gt;/);
  assert.match(result, /SKU-&lt;unsafe&gt;/);
});

test("renderOrder displays a semantic shipment summary and chronological timeline", () => {
  const result = renderOrder({
    id: "order-1001",
    status: "paid",
    totalCents: 7499,
    currency: "USD",
    items: [],
    shipment: {
      carrier: "UPS",
      trackingNumber: "1Z999AA10123456784",
      estimatedDeliveryDate: "2026-08-22",
      events: [
        {
          occurredAt: "2026-08-16T13:00:00Z",
          status: "label_created",
          description: "Shipping label created",
          location: "Toronto, ON"
        },
        {
          occurredAt: "2026-08-17T08:30:00Z",
          status: "in_transit",
          description: "Package departed the carrier facility",
          location: "Buffalo, NY"
        }
      ]
    }
  });

  assert.match(result, /<section class="shipment" aria-labelledby="shipment-heading">/);
  assert.match(result, /<h3 id="shipment-heading">Shipment<\/h3>/);
  assert.match(result, /<dl class="shipment-summary">[\s\S]*<dt>Carrier<\/dt>[\s\S]*<dd>UPS<\/dd>/);
  assert.match(result, /<dt>Tracking number<\/dt>[\s\S]*<dd>1Z999AA10123456784<\/dd>/);
  assert.match(result, /<time datetime="2026-08-22">August 22, 2026<\/time>/);
  assert.match(result, /<ol class="tracking-timeline" aria-labelledby="tracking-timeline-heading">/);
  assert.match(result, /<time datetime="2026-08-16T13:00:00Z">Aug 16, 2026, 1:00 PM UTC<\/time>/);
  assert.match(result, /<time datetime="2026-08-17T08:30:00Z">Aug 17, 2026, 8:30 AM UTC<\/time>/);
  assert.match(result, /Label Created/);
  assert.match(result, /In Transit/);
  assert.equal((result.match(/<li class="tracking-event">/g) ?? []).length, 2);
  assert.ok(result.indexOf("Shipping label created") < result.indexOf("Package departed"));
});

test("renderOrder escapes all shipment strings", () => {
  const result = renderOrder({
    id: "order-1001",
    status: "paid",
    totalCents: 7499,
    currency: "USD",
    items: [],
    shipment: {
      carrier: "<Carrier & Co>",
      trackingNumber: 'track<"unsafe">',
      estimatedDeliveryDate: "2026-08-22",
      events: [
        {
          occurredAt: '2026-08-16T13:00:00Z" onmouseover="alert(1)',
          status: "in_<transit>",
          description: "Package <strong>lost</strong>",
          location: "Toronto & area"
        }
      ]
    }
  });

  assert.doesNotMatch(result, /<Carrier|<strong>|onmouseover="/);
  assert.match(result, /&lt;Carrier &amp; Co&gt;/);
  assert.match(result, /track&lt;&quot;unsafe&quot;&gt;/);
  assert.match(result, /In &lt;Transit&gt;/);
  assert.match(result, /Package &lt;strong&gt;lost&lt;\/strong&gt;/);
  assert.match(result, /Toronto &amp; area/);
  assert.match(result, /datetime="2026-08-16T13:00:00Z&quot; onmouseover=&quot;alert\(1\)"/);
});
