import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const sourceDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = dirname(sourceDirectory);
const port = Number.parseInt(process.env.PORT ?? "3000", 10);
const routes = new Map([
  ["/", { path: join(repositoryRoot, "public/index.html"), type: "text/html; charset=utf-8" }],
  ["/app.js", { path: join(repositoryRoot, "public/app.js"), type: "text/javascript; charset=utf-8" }],
  ["/src/order-view.js", { path: join(sourceDirectory, "order-view.js"), type: "text/javascript; charset=utf-8" }]
]);

const server = createServer(async (request, response) => {
  const requestUrl = new URL(request.url ?? "/", "http://localhost");
  const route = routes.get(requestUrl.pathname);

  if (request.method !== "GET" || route === undefined) {
    response.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
    response.end("Not found");
    return;
  }

  try {
    const content = await readFile(route.path);
    response.writeHead(200, { "content-type": route.type });
    response.end(content);
  } catch {
    response.writeHead(500, { "content-type": "text/plain; charset=utf-8" });
    response.end("Could not load the application.");
  }
});

server.listen(port, "127.0.0.1", () => {
  console.log(`Acme Storefront listening on http://localhost:${port}`);
});
