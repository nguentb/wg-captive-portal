# wg-captive-portal

Web HTTP rieng cho captive portal, chi hien thong bao VPN het han. Dat server nay lam `PORTAL_IP` trong `wg-captive-agent`.

## Chay bang Node.js

```bash
sudo mkdir -p /opt/wg-captive-portal
sudo cp index.html server.js package.json /opt/wg-captive-portal/
sudo cp systemd/wg-captive-portal.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now wg-captive-portal
```

Mac dinh web nghe `0.0.0.0:80`. Neu muon doi port:

```bash
sudo systemctl edit wg-captive-portal
```

Them:

```ini
[Service]
Environment=PORT=8080
```

## Chay bang nginx

```bash
sudo mkdir -p /var/www/wg-captive-portal
sudo cp index.html /var/www/wg-captive-portal/index.html
sudo cp nginx.conf /etc/nginx/sites-available/wg-captive-portal
sudo ln -s /etc/nginx/sites-available/wg-captive-portal /etc/nginx/sites-enabled/wg-captive-portal
sudo nginx -t
sudo systemctl reload nginx
```

## Kiem tra

```bash
curl -i http://SERVER_IP/
curl -i http://SERVER_IP/generate_204
```

Moi URL HTTP deu nen tra ve trang `VPN het han`.
