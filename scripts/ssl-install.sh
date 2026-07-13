#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="${SERVICE_NAME:-wg-captive-portal}"
NGINX_SITE="${NGINX_SITE:-/etc/nginx/sites-available/wg-captive-portal}"
NGINX_ENABLED="${NGINX_ENABLED:-/etc/nginx/sites-enabled/wg-captive-portal}"
CREDENTIALS_FILE="${CLOUDFLARE_CREDENTIALS:-/etc/letsencrypt/wg-captive-cloudflare.ini}"
UPSTREAM="${UPSTREAM:-127.0.0.1:8080}"
DOMAIN="${DOMAIN:-}"
EMAIL="${EMAIL:-}"
CLOUDFLARE_TOKEN="${CLOUDFLARE_TOKEN:-}"
STAGING="${STAGING:-0}"

log() {
  printf '[ssl-install] %s\n' "$*"
}

fail() {
  printf '[ssl-install] ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  ssl-install [--domain domain.com] [--email admin@domain.com] [--cloudflare-token TOKEN] [--staging]

If values are omitted, ssl-install asks for them interactively.

Environment:
  UPSTREAM=127.0.0.1:8080
  NGINX_SITE=/etc/nginx/sites-available/wg-captive-portal
  CLOUDFLARE_CREDENTIALS=/etc/letsencrypt/wg-captive-cloudflare.ini
  STAGING=1
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)
      DOMAIN="${2:-}"
      shift 2
      ;;
    --admin-domain)
      shift 2
      ;;
    --email)
      EMAIL="${2:-}"
      shift 2
      ;;
    --cloudflare-token)
      CLOUDFLARE_TOKEN="${2:-}"
      shift 2
      ;;
    --staging)
      STAGING=1
      shift
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

[[ "${EUID}" -eq 0 ]] || fail "Please run as root: sudo ssl-install"

prompt() {
  local var_name="$1"
  local label="$2"
  local default_value="${3:-}"
  local secret="${4:-0}"
  local value=""
  if [[ -n "${!var_name:-}" ]]; then
    return
  fi
  if [[ "$secret" == "1" ]]; then
    printf '%s' "$label"
    if [[ -n "$default_value" ]]; then printf ' [%s]' "$default_value"; fi
    printf ': '
    read -r -s value
    printf '\n'
  else
    printf '%s' "$label"
    if [[ -n "$default_value" ]]; then printf ' [%s]' "$default_value"; fi
    printf ': '
    read -r value
  fi
  if [[ -z "$value" ]]; then value="$default_value"; fi
  printf -v "$var_name" '%s' "$value"
}

prompt DOMAIN "Portal domain" ""
DOMAIN="$(printf '%s' "$DOMAIN" | sed -E 's#^https?://##; s#/.*$##; s/[[:space:]]//g' | tr '[:upper:]' '[:lower:]')"
[[ -n "$DOMAIN" ]] || fail "Portal domain is required"

prompt EMAIL "Let's Encrypt email" "admin@${DOMAIN}"
[[ -n "$EMAIL" ]] || fail "Email is required"

prompt CLOUDFLARE_TOKEN "Cloudflare API token" "" 1
[[ -n "$CLOUDFLARE_TOKEN" ]] || fail "Cloudflare token is required"

if command -v apt-get >/dev/null 2>&1; then
  log "Installing certbot and Cloudflare DNS plugin"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates nginx certbot python3-certbot-dns-cloudflare
else
  log "apt-get not found; assuming nginx, certbot and python3-certbot-dns-cloudflare are installed"
fi

command -v nginx >/dev/null 2>&1 || fail "nginx is required"
command -v certbot >/dev/null 2>&1 || fail "certbot is required"

log "Writing Cloudflare credentials to ${CREDENTIALS_FILE}"
install -d -m 0700 "$(dirname "$CREDENTIALS_FILE")"
printf 'dns_cloudflare_api_token = %s\n' "$CLOUDFLARE_TOKEN" > "$CREDENTIALS_FILE"
chmod 0600 "$CREDENTIALS_FILE"

CERTBOT_ARGS=(
  certonly
  --dns-cloudflare
  --dns-cloudflare-credentials "$CREDENTIALS_FILE"
  --non-interactive
  --agree-tos
  --email "$EMAIL"
  --cert-name "$DOMAIN"
  -d "$DOMAIN"
)
if [[ "$STAGING" == "1" ]]; then
  CERTBOT_ARGS+=(--staging)
fi

log "Requesting certificate for ${DOMAIN}"
certbot "${CERTBOT_ARGS[@]}"

log "Writing nginx HTTPS config to ${NGINX_SITE}"
install -d -m 0755 "$(dirname "$NGINX_SITE")" "$(dirname "$NGINX_ENABLED")"
cat > "$NGINX_SITE" <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _ ${DOMAIN};
    return 302 https://${DOMAIN}\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;

    add_header Cache-Control "no-store, no-cache, must-revalidate, proxy-revalidate" always;
    add_header Pragma "no-cache" always;
    add_header Expires "0" always;

    location / {
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass http://${UPSTREAM};
    }
}
EOF

ln -sfn "$NGINX_SITE" "$NGINX_ENABLED"

log "Testing and reloading nginx"
nginx -t
systemctl reload nginx

log "SSL installed successfully"
log "Portal: https://${DOMAIN}"
