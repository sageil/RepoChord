import assert from "node:assert/strict";
import { createServer } from "node:http";
import test from "node:test";

import { createApp, createOrderStore } from "../src/app.js";

async function withServer(runTest, orderStore) {
  const app = orderStore === undefined ? createApp() : createApp(orderStore);
  const server = createServer(app);

  await new Promise((resolve) => {
    server.listen(0, "127.0.0.1", resolve);
  });

  try {
    const address = server.address();
    assert.notEqual(address, null);
    assert.equal(typeof address, "object");
    await runTest(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise((resolve, reject) => {
      server.close((error) => {
        if (error !== undefined) {
          reject(error);
          return;
        }

        resolve();
      });
    });
  }
}

test("GET /health returns service status", async () => {
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/health`);

    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { status: "ok" });
  });
});

test("GET /v1/orders/:id returns an existing order", async () => {
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/orders/order-1001`);

    assert.equal(response.status, 200);
    const order = await response.json();

    assert.deepEqual(order, {
      id: "order-1001",
      customerId: "customer-42",
      status: "paid",
      totalCents: 7499,
      currency: "USD",
      items: [
        {
          productName: "Wireless Keyboard",
          sku: "KB-WL-100",
          quantity: 2,
          unitPriceCents: 2500,
          lineSubtotalCents: 5000
        },
        {
          productName: "Desk Mat",
          sku: "MAT-DSK-001",
          quantity: 1,
          unitPriceCents: 2499,
          lineSubtotalCents: 2499
        }
      ],
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
            location: "Toronto, ON"
          },
          {
            occurredAt: "2026-08-18T14:15:00Z",
            status: "in_transit",
            description: "Package arrived at the carrier facility",
            location: "Buffalo, NY"
          }
        ]
      }
    });

    let itemSubtotalTotal = 0;

    for (const item of order.items) {
      assert.equal(typeof item.productName, "string");
      assert.equal(typeof item.sku, "string");
      assert.equal(Number.isInteger(item.quantity), true);
      assert.equal(item.quantity > 0, true);
      assert.equal(Number.isInteger(item.unitPriceCents), true);
      assert.equal(item.unitPriceCents >= 0, true);
      assert.equal(Number.isInteger(item.lineSubtotalCents), true);
      assert.equal(item.lineSubtotalCents >= 0, true);
      assert.equal(item.lineSubtotalCents, item.quantity * item.unitPriceCents);
      itemSubtotalTotal += item.lineSubtotalCents;
    }

    assert.equal(itemSubtotalTotal, order.totalCents);
  });
});

test("createOrderStore copies nested shipment data", () => {
  const firstStore = createOrderStore();
  const firstOrder = firstStore.get("order-1001");
  assert.notEqual(firstOrder, undefined);

  firstOrder.shipment.carrier = "Changed carrier";
  firstOrder.shipment.events[0].description = "Changed event";
  firstOrder.shipment.events.push({
    occurredAt: "2026-08-19T10:00:00Z",
    status: "delivered",
    description: "Changed event list",
    location: "New York, NY"
  });

  const secondStore = createOrderStore();
  const secondOrder = secondStore.get("order-1001");
  assert.notEqual(secondOrder, undefined);
  assert.equal(secondOrder.shipment.carrier, "UPS");
  assert.equal(secondOrder.shipment.events.length, 3);
  assert.equal(secondOrder.shipment.events[0].description, "Shipping label created");
  assert.notEqual(firstOrder.shipment, secondOrder.shipment);
  assert.notEqual(firstOrder.shipment.events, secondOrder.shipment.events);
  assert.notEqual(firstOrder.shipment.events[0], secondOrder.shipment.events[0]);
});

test("GET /v1/orders/:id/receipt returns a downloadable receipt", async () => {
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/orders/order-1001/receipt`);

    assert.equal(response.status, 200);
    assert.equal(response.headers.get("access-control-allow-origin"), "http://localhost:3000");
    assert.equal(response.headers.get("content-type"), "text/plain; charset=utf-8");
    assert.equal(
      response.headers.get("content-disposition"),
      'attachment; filename="order-1001-receipt.txt"'
    );
    const receipt = await response.text();

    assert.match(receipt, /Order number: order-1001/);
    assert.match(receipt, /Purchase status: Paid/);
    assert.match(receipt, /Customer number: customer-42/);
    assert.match(receipt, /Total: \$74\.99/);
  });
});

test("GET /v1/orders/:id returns 404 for an unknown order", async () => {
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/orders/missing`);

    assert.equal(response.status, 404);
    assert.deepEqual(await response.json(), { error: "order_not_found" });
  });
});

test("GET /v1/orders/:id/receipt returns 404 for an unknown order", async () => {
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/orders/missing/receipt`);

    assert.equal(response.status, 404);
    assert.equal(response.headers.get("content-type"), "application/json; charset=utf-8");
    assert.deepEqual(await response.json(), { error: "order_not_found" });
  });
});

test("GET /v1/orders/:id/receipt uses a safe attachment filename", async () => {
  const unsafeOrderId = "unsafe\r\nname";
  const orderStore = new Map([
    [
      unsafeOrderId,
      {
        id: unsafeOrderId,
        customerId: "customer-42",
        status: "payment_pending",
        totalCents: 100,
        currency: "USD",
        items: []
      }
    ]
  ]);

  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/orders/unsafe%0D%0Aname/receipt`);

    assert.equal(response.status, 200);
    assert.equal(
      response.headers.get("content-disposition"),
      'attachment; filename="unsafe__name-receipt.txt"'
    );
    assert.match(await response.text(), /Purchase status: Payment Pending/);
  }, orderStore);
});
