import { renderOrder } from "/src/order-view.js";

const applicationRoot = document.querySelector("#app");

async function loadOrder() {
  const response = await fetch("http://localhost:3001/v1/orders/order-1001");

  if (!response.ok) {
    throw new Error(`Order request failed with status ${response.status}.`);
  }

  return response.json();
}

try {
  const order = await loadOrder();
  applicationRoot.innerHTML = renderOrder(order);
} catch (error) {
  applicationRoot.textContent = error instanceof Error ? error.message : "Could not load the order.";
}
