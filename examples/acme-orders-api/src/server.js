import { createServer } from "node:http";

import { createApp } from "./app.js";

const port = Number.parseInt(process.env.PORT ?? "3001", 10);
const server = createServer(createApp());

server.listen(port, "127.0.0.1", () => {
  console.log(`Acme Orders API listening on http://localhost:${port}`);
});
