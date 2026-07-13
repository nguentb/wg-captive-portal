#!/usr/bin/env node
"use strict";

const fs = require("fs");
const http = require("http");
const https = require("https");
const path = require("path");
const crypto = require("crypto");
const { URL } = require("url");

const host = process.env.HOST || "0.0.0.0";
const port = Number(process.env.PORT || "80");
const indexPath = path.join(__dirname, "index.html");
const html = fs.readFileSync(indexPath);
const nodeStorePath = process.env.NODE_STORE || "/etc/wg-captive-portal-nodes.json";
const adminPassword = process.env.ADMIN_PASSWORD || "change-this-password";
const sessionSecret = process.env.SESSION_SECRET || adminPassword;

function sendJson(res, code, payload) {
  res.writeHead(code, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store, no-cache, must-revalidate, proxy-revalidate",
    "Pragma": "no-cache",
    "Expires": "0",
  });
  res.end(JSON.stringify(payload));
}

function sendHtml(res, body) {
  res.writeHead(200, {
    "Content-Type": "text/html; charset=utf-8",
    "Cache-Control": "no-store, no-cache, must-revalidate, proxy-revalidate",
    "Pragma": "no-cache",
    "Expires": "0",
  });
  res.end(body);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let body = "";
    req.setEncoding("utf8");
    req.on("data", (chunk) => {
      body += chunk;
      if (body.length > 1024 * 1024) req.destroy(new Error("Request body too large"));
    });
    req.on("end", () => resolve(body));
    req.on("error", reject);
  });
}

async function readJsonBody(req) {
  const raw = await readBody(req);
  if (!raw) return {};
  return JSON.parse(raw);
}

function hostname(req) {
  return String(req.headers.host || "").split(":")[0].toLowerCase();
}

function isAdminHost(req) {
  const name = hostname(req);
  const configured = String(process.env.ADMIN_HOST || "").toLowerCase();
  if (configured && name === configured) return true;
  return name.startsWith("adm.");
}

function loadStoredNodes() {
  try {
    const data = JSON.parse(fs.readFileSync(nodeStorePath, "utf8"));
    return Array.isArray(data.nodes) ? data.nodes : [];
  } catch {
    return [];
  }
}

function saveStoredNodes(nodes) {
  fs.mkdirSync(path.dirname(nodeStorePath), { recursive: true });
  fs.writeFileSync(nodeStorePath, JSON.stringify({ nodes }, null, 2));
}

function normalizeBaseUrl(value) {
  const input = String(value || "").trim().replace(/\/+$/, "");
  if (!input) return "";
  if (!/^https?:\/\//i.test(input)) return `https://${input}`;
  return input;
}

function safeNodeName(value) {
  return String(value || "").trim().replace(/[^A-Za-z0-9_.-]/g, "");
}

function publicNode(node) {
  const token = String(node.token || "");
  return {
    name: node.name,
    baseUrl: node.baseUrl,
    tokenPrefix: token ? `${token.slice(0, 8)}...` : "",
    hasToken: Boolean(token),
    updatedAt: node.updatedAt || "",
  };
}

function upsertNode(input) {
  const name = safeNodeName(input.name);
  const baseUrl = normalizeBaseUrl(input.baseUrl);
  if (!name) throw new Error("Missing server name");
  if (!baseUrl) throw new Error("Missing node API address");
  const nodes = loadStoredNodes();
  const index = nodes.findIndex((item) => item.name === name);
  const previous = index >= 0 ? nodes[index] : {};
  const token = String(input.token || "").trim() || previous.token || "";
  const next = { name, baseUrl, token, updatedAt: new Date().toISOString() };
  if (index >= 0) nodes[index] = next;
  else nodes.push(next);
  nodes.sort((a, b) => a.name.localeCompare(b.name));
  saveStoredNodes(nodes);
  return next;
}

function deleteNode(name) {
  const cleanName = safeNodeName(name);
  const nodes = loadStoredNodes();
  const next = nodes.filter((item) => item.name !== cleanName);
  saveStoredNodes(next);
  return next.length !== nodes.length;
}

function envNodeConfigs() {
  if (process.env.NODE_API_CONFIG) {
    try {
      return JSON.parse(process.env.NODE_API_CONFIG);
    } catch {
      return {};
    }
  }
  if (process.env.NODE_API_BASE) {
    return {
      [process.env.NODE_NAME || "default"]: {
        baseUrl: process.env.NODE_API_BASE,
        token: process.env.NODE_API_TOKEN || "",
      },
    };
  }
  return {};
}

function nodeConfigs() {
  const configs = { ...envNodeConfigs() };
  for (const node of loadStoredNodes()) {
    configs[node.name] = { baseUrl: node.baseUrl, token: node.token || "" };
  }
  return configs;
}

function cookieValue(req, key) {
  const cookie = String(req.headers.cookie || "");
  for (const part of cookie.split(";")) {
    const [name, ...rest] = part.trim().split("=");
    if (name === key) return decodeURIComponent(rest.join("="));
  }
  return "";
}

function signSession(value) {
  return crypto.createHmac("sha256", sessionSecret).update(value).digest("hex");
}

function isAdminAuthed(req) {
  const value = cookieValue(req, "portal_admin");
  if (!value) return false;
  const [user, sig] = value.split(".");
  return user === "admin" && sig === signSession(user);
}

function setAdminCookie(res) {
  const value = `admin.${signSession("admin")}`;
  res.setHeader("Set-Cookie", `portal_admin=${encodeURIComponent(value)}; HttpOnly; SameSite=Lax; Path=/; Max-Age=2592000`);
}

function clearAdminCookie(res) {
  res.setHeader("Set-Cookie", "portal_admin=; HttpOnly; SameSite=Lax; Path=/; Max-Age=0");
}

function apiGetJson(baseUrl, token, pathname) {
  return new Promise((resolve, reject) => {
    const target = new URL(pathname, baseUrl.endsWith("/") ? baseUrl : `${baseUrl}/`);
    const client = target.protocol === "https:" ? https : http;
    const req = client.request(target, {
      method: "GET",
      headers: token ? { Authorization: `Bearer ${token}` } : {},
      timeout: 8000,
    }, (response) => {
      let body = "";
      response.setEncoding("utf8");
      response.on("data", (chunk) => { body += chunk; });
      response.on("end", () => {
        try {
          const data = JSON.parse(body || "{}");
          if (response.statusCode < 200 || response.statusCode >= 300) {
            const err = new Error(data.error || `Node API returned ${response.statusCode}`);
            err.statusCode = response.statusCode;
            reject(err);
            return;
          }
          resolve(data);
        } catch (error) {
          reject(error);
        }
      });
    });
    req.on("timeout", () => req.destroy(new Error("Node API timeout")));
    req.on("error", reject);
    req.end();
  });
}

function clientStatus(client) {
  if (client?.expired) return "expired";
  if (client?.disabled || client?.enabled === false) return "disabled";
  return client ? "active" : "unknown";
}

async function lookupClient(node, ip) {
  const configs = nodeConfigs();
  const config = configs[node] || configs.default;
  if (!config?.baseUrl) throw new Error("Node API is not configured");
  let client;
  try {
    const data = await apiGetJson(config.baseUrl, config.token || "", `/api/v1/clients/${encodeURIComponent(ip)}`);
    client = data.client;
  } catch (error) {
    if (error.statusCode && error.statusCode !== 404) throw error;
    const data = await apiGetJson(config.baseUrl, config.token || "", "/api/v1/clients");
    client = (data.clients || []).find((item) => item.ip === ip);
  }
  if (!client) return { node, ip, found: false, status: "unknown" };
  return {
    node,
    ip,
    found: true,
    name: client.name || "",
    status: client.status || clientStatus(client),
    expires_at: client.expires_at || "",
    disabled: Boolean(client.disabled),
    expired: Boolean(client.expired),
  };
}

function adminPage() {
  return `<!doctype html>
<html lang="vi">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Portal Admin</title>
  <style>
    *{box-sizing:border-box}body{margin:0;min-height:100vh;background:#0b1220;color:#f8fafc;font-family:Inter,ui-sans-serif,system-ui,"Segoe UI",Arial,sans-serif}.shell{width:min(1040px,100%);margin:0 auto;padding:28px 16px}.top{display:flex;align-items:center;justify-content:space-between;gap:16px;margin-bottom:18px}.brand h1{margin:0;font-size:30px}.brand p{margin:6px 0 0;color:#93a4bc}.panel{background:linear-gradient(180deg,#111c2f,#0d1728);border:1px solid rgba(148,163,184,.16);border-radius:16px;padding:18px;box-shadow:0 24px 70px rgba(0,0,0,.34)}form.grid{display:grid;grid-template-columns:1fr 1.4fr 1.2fr auto;gap:10px;align-items:end}label{display:grid;gap:7px;color:#c7d2e2;font-size:13px;font-weight:800}input{min-width:0;border:1px solid #263449;background:#08111f;color:#f8fafc;border-radius:11px;padding:12px;font:inherit;font-weight:700}button{border:0;border-radius:11px;padding:12px 15px;font:inherit;font-weight:850;color:#fff;background:#2f6df6;cursor:pointer}button.ghost{background:#334155}button.danger{background:#991b1b}.login{min-height:100vh;display:grid;place-items:center;padding:18px}.login .panel{width:min(420px,100%)}.login h1{margin:0 0 16px}.login form{display:grid;gap:12px}.table{display:grid;gap:9px;margin-top:16px}.row{display:grid;grid-template-columns:1fr 1.5fr .8fr auto;gap:10px;align-items:center;padding:12px;border:1px solid rgba(38,52,73,.9);border-radius:12px;background:#0b1424}.muted{color:#93a4bc;font-size:13px}.name{font-weight:900}.toast{position:fixed;right:16px;bottom:16px;background:#e5e7eb;color:#0f172a;border-radius:12px;padding:12px 14px;font-weight:800;opacity:0;transform:translateY(10px);transition:.18s}.toast.show{opacity:1;transform:none}@media(max-width:760px){form.grid,.row{grid-template-columns:1fr}.top{align-items:flex-start;flex-direction:column}}
  </style>
</head>
<body>
  <div class="shell">
    <div class="top">
      <div class="brand"><h1>Portal Admin</h1><p>Quan ly danh sach node WireGuard cho captive portal.</p></div>
      <form method="post" action="/logout"><button class="ghost" type="submit">Logout</button></form>
    </div>
    <section class="panel">
      <form id="nodeForm" class="grid">
        <label>Server name<input id="name" name="name" placeholder="wg-server-01" required></label>
        <label>Node API address<input id="baseUrl" name="baseUrl" placeholder="https://wg.example.com:51822" required></label>
        <label>API token<input id="token" name="token" placeholder="De trong neu giu token cu"></label>
        <button type="submit">Save node</button>
      </form>
      <div id="nodeList" class="table"></div>
    </section>
  </div>
  <div id="toast" class="toast"></div>
  <script>
    const $=(id)=>document.getElementById(id);
    function toast(message){const el=$('toast');el.textContent=message;el.classList.add('show');setTimeout(()=>el.classList.remove('show'),2200)}
    async function api(url,options){const res=await fetch(url,{headers:{'Content-Type':'application/json'},...options});const data=await res.json();if(!res.ok||data.ok===false)throw new Error(data.error||'Request failed');return data}
    function render(nodes){const box=$('nodeList');if(!nodes.length){box.innerHTML='<div class="muted">Chua co node nao.</div>';return}box.innerHTML=nodes.map((n)=>'<div class="row"><div><div class="name">'+escapeHtml(n.name)+'</div><div class="muted">'+escapeHtml(n.updatedAt||'')+'</div></div><div>'+escapeHtml(n.baseUrl)+'</div><div class="muted">Token: '+escapeHtml(n.tokenPrefix||'none')+'</div><div><button class="ghost edit" data-name="'+escapeHtml(n.name)+'" data-url="'+escapeHtml(n.baseUrl)+'">Edit</button> <button class="danger del" data-name="'+escapeHtml(n.name)+'">Delete</button></div></div>').join('')}
    function escapeHtml(v){return String(v||'').replace(/[&<>"']/g,(c)=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
    async function load(){const data=await api('/api/admin/nodes');render(data.nodes||[])}
    $('nodeForm').addEventListener('submit',async(e)=>{e.preventDefault();const payload=Object.fromEntries(new FormData(e.target).entries());try{const data=await api('/api/admin/nodes',{method:'POST',body:JSON.stringify(payload)});render(data.nodes||[]);$('token').value='';toast('Da luu node')}catch(error){toast(error.message)}})
    $('nodeList').addEventListener('click',async(e)=>{const edit=e.target.closest('.edit');const del=e.target.closest('.del');if(edit){$('name').value=edit.dataset.name;$('baseUrl').value=edit.dataset.url;$('token').value='';$('name').focus();return}if(del){if(!confirm('Xoa node '+del.dataset.name+'?'))return;try{const data=await api('/api/admin/nodes/'+encodeURIComponent(del.dataset.name),{method:'DELETE'});render(data.nodes||[]);toast('Da xoa node')}catch(error){toast(error.message)}}})
    load().catch((error)=>toast(error.message));
  </script>
</body>
</html>`;
}

function loginPage(error = "") {
  return `<!doctype html><html lang="vi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Portal Admin Login</title><style>*{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;background:#0b1220;color:#f8fafc;font-family:system-ui,"Segoe UI",Arial,sans-serif}.panel{width:min(420px,calc(100% - 28px));background:#111c2f;border:1px solid rgba(148,163,184,.16);border-radius:16px;padding:24px;box-shadow:0 24px 70px rgba(0,0,0,.34)}h1{margin:0 0 16px}form{display:grid;gap:12px}input,button{border-radius:12px;padding:13px;font:inherit}input{border:1px solid #263449;background:#08111f;color:#fff}button{border:0;background:#2f6df6;color:#fff;font-weight:850}.err{color:#fecaca;margin:0 0 12px}</style></head><body><main class="panel"><h1>Portal Admin</h1>${error ? `<p class="err">${error}</p>` : ""}<form method="post" action="/login"><input type="password" name="password" placeholder="Admin password" autofocus><button type="submit">Login</button></form></main></body></html>`;
}

async function handleAdmin(req, res, url) {
  if (req.method === "POST" && url.pathname === "/login") {
    const body = new URLSearchParams(await readBody(req));
    if (String(body.get("password") || "") === adminPassword) {
      setAdminCookie(res);
      res.writeHead(302, { Location: "/" });
      return res.end();
    }
    return sendHtml(res, loginPage("Sai mat khau"));
  }
  if (req.method === "POST" && url.pathname === "/logout") {
    clearAdminCookie(res);
    res.writeHead(302, { Location: "/" });
    return res.end();
  }
  if (!isAdminAuthed(req)) return sendHtml(res, loginPage());
  if (req.method === "GET" && url.pathname === "/api/admin/nodes") {
    return sendJson(res, 200, { ok: true, nodes: loadStoredNodes().map(publicNode) });
  }
  if (req.method === "POST" && url.pathname === "/api/admin/nodes") {
    try {
      upsertNode(await readJsonBody(req));
      return sendJson(res, 200, { ok: true, nodes: loadStoredNodes().map(publicNode) });
    } catch (error) {
      return sendJson(res, 400, { ok: false, error: error.message });
    }
  }
  const deleteMatch = url.pathname.match(/^\/api\/admin\/nodes\/([^/]+)$/);
  if (req.method === "DELETE" && deleteMatch) {
    deleteNode(decodeURIComponent(deleteMatch[1]));
    return sendJson(res, 200, { ok: true, nodes: loadStoredNodes().map(publicNode) });
  }
  return sendHtml(res, adminPage());
}

async function handlePortal(req, res, url) {
  if (url.pathname === "/api/client-info") {
    const node = String(url.searchParams.get("node") || "").trim();
    const ip = String(url.searchParams.get("ip") || "").trim();
    if (!node || !ip) return sendJson(res, 400, { ok: false, error: "Missing node or ip" });
    try {
      return sendJson(res, 200, { ok: true, client: await lookupClient(node, ip) });
    } catch (error) {
      return sendJson(res, 502, { ok: false, error: error.message, client: { node, ip, status: "unknown" } });
    }
  }
  return sendHtml(res, html);
}

http.createServer(async (req, res) => {
  const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);
  try {
    if (isAdminHost(req)) return await handleAdmin(req, res, url);
    return await handlePortal(req, res, url);
  } catch (error) {
    console.error(error);
    return sendJson(res, 500, { ok: false, error: error.message });
  }
}).listen(port, host, () => {
  console.log(`wg-captive-portal listening on http://${host}:${port}`);
});