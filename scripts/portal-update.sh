#!/usr/bin/env bash
set -euo pipefail

REPO="${WG_CAPTIVE_PORTAL_REPO:-nguentb/wg-captive-portal}"
BRANCH="${WG_CAPTIVE_PORTAL_BRANCH:-main}"
TARBALL_URL="${WG_CAPTIVE_PORTAL_TARBALL_URL:-https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz}"
INSTALL_DIR="${INSTALL_DIR:-/opt/wg-captive-portal}"
SERVICE_NAME="${SERVICE_NAME:-wg-captive-portal}"
DOMAIN="${DOMAIN:-}"
TMP_DIR=""

log() {
  printf '[portal-update] %s\n' "$*"
}

fail() {
  printf '[portal-update] ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  portal-update [--branch main] [--repo owner/repo] [--domain domain.com]

Options:
  --branch BRANCH       GitHub branch, default main.
  --repo OWNER/REPO     GitHub repo, default nguentb/wg-captive-portal.
  --domain DOMAIN       Only used to create nginx HTTP config if it is missing.

Environment overrides:
  INSTALL_DIR=/opt/wg-captive-portal
  SERVICE_NAME=wg-captive-portal
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
    --domain)
      DOMAIN="${2:-}"
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

[[ "${EUID}" -eq 0 ]] || fail "Please run as root: sudo portal-update"
[[ -n "$INSTALL_DIR" && "$INSTALL_DIR" != "/" ]] || fail "Refusing unsafe INSTALL_DIR: ${INSTALL_DIR}"

if command -v apt-get >/dev/null 2>&1; then
  log "Ensuring required packages"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl tar nginx nodejs
fi

command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v tar >/dev/null 2>&1 || fail "tar is required"
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

log "Updating application files in ${INSTALL_DIR}"
install -d -m 0755 "$INSTALL_DIR"
install -m 0644 "$SRC_DIR/index.html" "$INSTALL_DIR/index.html"
install -m 0755 "$SRC_DIR/server.js" "$INSTALL_DIR/server.js"
install -m 0644 "$SRC_DIR/package.json" "$INSTALL_DIR/package.json"
install -m 0755 "$SRC_DIR/scripts/ssl-install.sh" /usr/local/sbin/ssl-install
install -m 0755 "$SRC_DIR/scripts/portal-update.sh" /usr/local/sbin/portal-update
install -m 0755 "$SRC_DIR/scripts/portal-uninstall.sh" /usr/local/sbin/portal-uninstall

log "Updating systemd unit"
install -m 0644 "$SRC_DIR/systemd/wg-captive-portal.service" "/etc/systemd/system/${SERVICE_NAME}.service"
systemctl daemon-reload

NGINX_SITE="/etc/nginx/sites-available/${SERVICE_NAME}"
NGINX_ENABLED="/etc/nginx/sites-enabled/${SERVICE_NAME}"
if [[ ! -f "$NGINX_SITE" ]]; then
  log "Creating missing nginx HTTP config"
  install -d -m 0755 /etc/nginx/sites-available /etc/nginx/sites-enabled
  install -m 0644 "$SRC_DIR/nginx.conf" "$NGINX_SITE"
  if [[ -n "$DOMAIN" ]]; then
    sed -i "s/server_name _;/server_name ${DOMAIN};/" "$NGINX_SITE"
  fi
  ln -sfn "$NGINX_SITE" "$NGINX_ENABLED"
fi

log "Restarting services"
systemctl enable "$SERVICE_NAME" >/dev/null
systemctl restart "$SERVICE_NAME"
if command -v nginx >/dev/null 2>&1; then
  nginx -t
  systemctl reload nginx
fi

log "Update complete"
log "Admin: /admin"
log "SSL installer: sudo ssl-install"
log "Uninstall: sudo portal-uninstall"
