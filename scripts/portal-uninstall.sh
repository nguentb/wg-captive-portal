#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="${SERVICE_NAME:-wg-captive-portal}"
INSTALL_DIR="${INSTALL_DIR:-/opt/wg-captive-portal}"
NGINX_SITE="${NGINX_SITE:-/etc/nginx/sites-available/wg-captive-portal}"
NGINX_ENABLED="${NGINX_ENABLED:-/etc/nginx/sites-enabled/wg-captive-portal}"
CREDENTIALS_FILE="${CLOUDFLARE_CREDENTIALS:-/etc/letsencrypt/wg-captive-cloudflare.ini}"
DOMAIN="${DOMAIN:-}"
YES=0
PURGE_SSL=0

log() {
  printf '[portal-uninstall] %s\n' "$*"
}

fail() {
  printf '[portal-uninstall] ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  portal-uninstall [--yes] [--purge-ssl --domain domain.com]

Options:
  --yes             Do not ask for confirmation.
  --purge-ssl       Also delete certbot certificate and Cloudflare credentials.
  --domain DOMAIN   Certbot cert name to delete when using --purge-ssl.

Environment overrides:
  INSTALL_DIR=/opt/wg-captive-portal
  NGINX_SITE=/etc/nginx/sites-available/wg-captive-portal
  CLOUDFLARE_CREDENTIALS=/etc/letsencrypt/wg-captive-cloudflare.ini
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y)
      YES=1
      shift
      ;;
    --purge-ssl)
      PURGE_SSL=1
      shift
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

[[ "${EUID}" -eq 0 ]] || fail "Please run as root: sudo portal-uninstall"
[[ -n "$INSTALL_DIR" && "$INSTALL_DIR" != "/" ]] || fail "Refusing unsafe INSTALL_DIR: ${INSTALL_DIR}"

if [[ "$YES" != "1" ]]; then
  printf 'This will remove wg-captive-portal service, nginx site, app files and CLI commands. Continue? [y/N]: '
  read -r answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *) log "Cancelled"; exit 0 ;;
  esac
fi

log "Stopping service"
systemctl disable --now "$SERVICE_NAME" >/dev/null 2>&1 || true

log "Removing systemd unit"
rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
rm -rf "/etc/systemd/system/${SERVICE_NAME}.service.d"
systemctl daemon-reload

log "Removing nginx site"
rm -f "$NGINX_ENABLED"
rm -f "$NGINX_SITE"
if command -v nginx >/dev/null 2>&1; then
  nginx -t && systemctl reload nginx || true
fi

log "Removing application files and CLI commands"
rm -rf "$INSTALL_DIR"
rm -f /usr/local/sbin/ssl-install
rm -f /usr/local/sbin/portal-update
rm -f /usr/local/sbin/portal-uninstall
`n
if [[ "$PURGE_SSL" == "1" ]]; then
  if [[ -n "$DOMAIN" && -x "$(command -v certbot || true)" ]]; then
    log "Deleting certbot certificate ${DOMAIN}"
    certbot delete --cert-name "$DOMAIN" --non-interactive || true
  elif [[ -z "$DOMAIN" ]]; then
    log "Skipping certbot certificate delete because --domain was not provided"
  fi
  log "Removing Cloudflare credentials"
  rm -f "$CREDENTIALS_FILE"
else
  log "Keeping SSL certificates and credentials"
fi

log "Uninstall complete"
