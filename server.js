#!/usr/bin/env node
"use strict";

const fs = require("fs");
const http = require("http");
const path = require("path");
const { URL } = require("url");

const host = process.env.HOST || "0.0.0.0";
const port = Number(process.env.PORT || "80");
const indexPath = path.join(__dirname, "index.html");
const html = fs.readFileSync(indexPath);

function noStoreHeaders(extra = {}) {
  return {
    "Cache-Control": "no-store, no-cache, must-revalidate, proxy-revalidate",
    "Pragma": "no-cache",
    "Expires": "0",
    ...extra,
  };
}

function sendHtml(res, code, body) {
  res.writeHead(code, noStoreHeaders({ "Content-Type": "text/html; charset=utf-8" }));
  res.end(body);
}

http.createServer((req, res) => {
  try {
    new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);
    return sendHtml(res, 200, html);
  } catch (error) {
    console.error(error);
    return sendHtml(res, 500, "Internal server error");
  }
}).listen(port, host, () => {
  console.log(`wg-captive-portal listening on http://${host}:${port}`);
});
