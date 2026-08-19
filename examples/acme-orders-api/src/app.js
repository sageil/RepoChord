const initialOrders = [
  {
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
  }
];

function writeJson(response, statusCode, body) {
  response.writeHead(statusCode, {
    "access-control-allow-origin": "http://localhost:3000",
    "content-type": "application/json; charset=utf-8"
  });
  response.end(JSON.stringify(body));
}

function formatPurchaseStatus(status) {
  const words = status.split("_");
  const formattedWords = [];

  for (const word of words) {
    const formattedWord = word.charAt(0).toUpperCase() + word.slice(1).toLowerCase();
    formattedWords.push(formattedWord);
  }

  return formattedWords.join(" ");
}

function createSafeReceiptFilename(orderId) {
  const hasSafeCharacter = /[A-Za-z0-9._-]/.test(orderId);
  const safeOrderId = hasSafeCharacter
    ? orderId.replace(/[^A-Za-z0-9._-]/g, "_")
    : "order";

  return `${safeOrderId}-receipt.txt`;
}

function createReceipt(order) {
  const total = new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: order.currency
  }).format(order.totalCents / 100);

  return [
    `Order number: ${order.id}`,
    `Purchase status: ${formatPurchaseStatus(order.status)}`,
    `Customer number: ${order.customerId}`,
    `Total: ${total}`,
    ""
  ].join("\n");
}

function writeReceipt(response, order) {
  response.writeHead(200, {
    "access-control-allow-origin": "http://localhost:3000",
    "content-disposition": `attachment; filename="${createSafeReceiptFilename(order.id)}"`,
    "content-type": "text/plain; charset=utf-8"
  });
  response.end(createReceipt(order));
}

export function createOrderStore() {
  const orders = new Map();

  for (const order of initialOrders) {
    const items = order.items.map((item) => ({ ...item }));
    const events = order.shipment.events.map((event) => ({ ...event }));
    const shipment = { ...order.shipment, events };
    orders.set(order.id, { ...order, items, shipment });
  }

  return orders;
}

export function createApp(orderStore = createOrderStore()) {
  return function handleRequest(request, response) {
    const requestUrl = new URL(request.url ?? "/", "http://localhost");

    if (request.method === "GET" && requestUrl.pathname === "/health") {
      writeJson(response, 200, { status: "ok" });
      return;
    }

    const receiptMatch = requestUrl.pathname.match(/^\/v1\/orders\/([^/]+)\/receipt$/);

    if (request.method === "GET" && receiptMatch !== null) {
      const orderId = decodeURIComponent(receiptMatch[1]);
      const order = orderStore.get(orderId);

      if (order === undefined) {
        writeJson(response, 404, { error: "order_not_found" });
        return;
      }

      writeReceipt(response, order);
      return;
    }

    const orderMatch = requestUrl.pathname.match(/^\/v1\/orders\/([^/]+)$/);

    if (request.method === "GET" && orderMatch !== null) {
      const orderId = decodeURIComponent(orderMatch[1]);
      const order = orderStore.get(orderId);

      if (order === undefined) {
        writeJson(response, 404, { error: "order_not_found" });
        return;
      }

      writeJson(response, 200, order);
      return;
    }

    writeJson(response, 404, { error: "route_not_found" });
  };
}
