#!/usr/bin/env bash
set -euo pipefail

REPO="${WG_CAPTIVE_PORTAL_REPO:-nguentb/wg-captive-portal}"
BRANCH="${WG_CAPTIVE_PORTAL_BRANCH:-main}"
TARBALL_URL="${WG_CAPTIVE_PORTAL_TARBALL_URL:-https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz}"
INSTALL_DIR="${INSTALL_DIR:-/opt/wg-captive-portal}"
SERVICE_NAME="wg-captive-portal"
NODE_STORE="${NODE_STORE:-/etc/wg-captive-portal-nodes.json}"
HOST_VALUE="${HOST:-127.0.0.1}"
PORT_VALUE="${PORT:-8080}"
DOMAIN="${DOMAIN:-}"
ADMIN_DOMAIN="${ADMIN_DOMAIN:-}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
DISABLE_NGINX_DEFAULT="${DISABLE_NGINX_DEFAULT:-1}"
TMP_DIR=""

log() {
  printf '[wg-captive-portal] %s\n' "$*"
}

fail() {
  printf '[wg-captive-portal] ERROR: %s\n' "$*" >&2
  exit 1
}

systemd_env_value() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "$value"
}
usage() {
  cat <<'EOF'
Usage:
  install-remote.sh --domain domain.com --admin-domain adm.domain.com [--admin-password PASSWORD]

Options:
  --domain DOMAIN             User portal domain, for example domain.com.
  --admin-domain DOMAIN       Admin portal domain, for example adm.domain.com.
  --admin-password PASSWORD   Admin password. Generated if omitted.
  --branch BRANCH             GitHub branch, default main.
  --repo OWNER/REPO           GitHub repo, default nguentb/wg-captive-portal.

Environment overrides:
  INSTALL_DIR=/opt/wg-captive-portal
  HOST=127.0.0.1
  PORT=8080
  NODE_STORE=/etc/wg-captive-portal-nodes.json
  DISABLE_NGINX_DEFAULT=1
EOF
}

cleanup() {
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)
      DOMAIN="${2:-}"
      shift 2
      ;;
    --admin-domain)
      ADMIN_DOMAIN="${2:-}"
      shift 2
      ;;
    --admin-password)
      ADMIN_PASSWORD="${2:-}"
      shift 2
      ;;
    --branch)
      BRANCH="${2:-}"
      TARBALL_URL="https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz"
      shift 2
      ;;
    --repo)
      REPO="${2:-}"
      TARBALL_URL="https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
done

[[ "${EUID}" -eq 0 ]] || fail "Please run as root, for example: curl -fsSL ... | sudo bash -s -- --domain domain.com --admin-domain adm.domain.com"
[[ -n "$DOMAIN" ]] || fail "--domain is required"
[[ -n "$ADMIN_DOMAIN" ]] || fail "--admin-domain is required"

if [[ -z "$ADMIN_PASSWORD" ]]; then
  if command -v openssl >/dev/null 2>&1; then
    ADMIN_PASSWORD="$(openssl rand -hex 16 | tr -d '\n')"
  else
    ADMIN_PASSWORD="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)"
  fi
fi

if command -v apt-get >/dev/null 2>&1; then
  log "Installing dependencies with apt-get"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl tar nginx nodejs
else
  log "apt-get not found; assuming curl, tar, nginx and nodejs are installed"
fi

command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v tar >/dev/null 2>&1 || fail "tar is required"
command -v nginx >/dev/null 2>&1 || fail "nginx is required"
command -v node >/dev/null 2>&1 || fail "nodejs is required"

NODE_MAJOR="$(node -p 'parseInt(process.versions.node.split(".")[0], 10)' 2>/dev/null || echo 0)"
if [[ "$NODE_MAJOR" -lt 18 ]]; then
  fail "Node.js 18+ is required; current version is $(node -v 2>/dev/null || echo unknown)"
fi

TMP_DIR="$(mktemp -d)"
log "Downloading ${TARBALL_URL}"
curl -fsSL "$TARBALL_URL" -o "$TMP_DIR/source.tar.gz"
tar -xzf "$TMP_DIR/source.tar.gz" -C "$TMP_DIR"
SRC_DIR="$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
[[ -n "$SRC_DIR" && -f "$SRC_DIR/server.js" && -f "$SRC_DIR/index.html" ]] || fail "Downloaded archive is not wg-captive-portal"

log "Installing files to ${INSTALL_DIR}"
install -d -m 0755 "$INSTALL_DIR"
install -m 0644 "$SRC_DIR/index.html" "$INSTALL_DIR/index.html"
install -m 0755 "$SRC_DIR/server.js" "$INSTALL_DIR/server.js"
install -m 0644 "$SRC_DIR/package.json" "$INSTALL_DIR/package.json"
install -m 0755 "$SRC_DIR/scripts/ssl-install.sh" /usr/local/sbin/ssl-install

install -m 0644 "$SRC_DIR/systemd/wg-captive-portal.service" "/etc/systemd/system/${SERVICE_NAME}.service"
install -d -m 0755 "/etc/systemd/system/${SERVICE_NAME}.service.d"
cat > "/etc/systemd/system/${SERVICE_NAME}.service.d/override.conf" <<EOF
[Service]
Environment=HOST=$(systemd_env_value "$HOST_VALUE")
Environment=PORT=$(systemd_env_value "$PORT_VALUE")
Environment=ADMIN_PASSWORD=$(systemd_env_value "$ADMIN_PASSWORD")
Environment=ADMIN_HOST=$(systemd_env_value "$ADMIN_DOMAIN")
Environment=NODE_STORE=$(systemd_env_value "$NODE_STORE")
EOF

log "Configuring nginx"
install -d -m 0755 /etc/nginx/sites-available /etc/nginx/sites-enabled
install -m 0644 "$SRC_DIR/nginx.conf" "/etc/nginx/sites-available/${SERVICE_NAME}"
if [[ -n "$DOMAIN" || -n "$ADMIN_DOMAIN" ]]; then
  sed -i "s/server_name _;/server_name ${DOMAIN} ${ADMIN_DOMAIN};/" "/etc/nginx/sites-available/${SERVICE_NAME}"
fi
ln -sfn "/etc/nginx/sites-available/${SERVICE_NAME}" "/etc/nginx/sites-enabled/${SERVICE_NAME}"
if [[ "$DISABLE_NGINX_DEFAULT" == "1" && -L /etc/nginx/sites-enabled/default ]]; then
  rm -f /etc/nginx/sites-enabled/default
fi

log "Starting services"
systemctl daemon-reload
systemctl enable "$SERVICE_NAME" >/dev/null
systemctl restart "$SERVICE_NAME"
systemctl enable --now nginx >/dev/null
nginx -t
systemctl reload nginx

log "Installed successfully"
log "Portal: http://${DOMAIN}"
log "Admin:  http://${ADMIN_DOMAIN}"
log "Admin password: ${ADMIN_PASSWORD}"
log "Node store: ${NODE_STORE}"
log "SSL installer: sudo ssl-install"
