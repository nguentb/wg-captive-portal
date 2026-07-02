#!/usr/bin/env node
"use strict";

const fs = require("fs");
const http = require("http");
const path = require("path");

const host = process.env.HOST || "0.0.0.0";
const port = Number(process.env.PORT || "80");
const indexPath = path.join(__dirname, "index.html");
const html = fs.readFileSync(indexPath);

http.createServer((_req, res) => {
  res.writeHead(200, {
    "Content-Type": "text/html; charset=utf-8",
    "Cache-Control": "no-store, no-cache, must-revalidate, proxy-revalidate",
    "Pragma": "no-cache",
    "Expires": "0",
  });
  res.end(html);
}).listen(port, host, () => {
  console.log(`wg-captive-portal listening on http://${host}:${port}`);
});
