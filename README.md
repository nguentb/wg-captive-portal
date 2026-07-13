# wg-captive-portal

Web HTTP/HTTPS rieng cho captive portal. Dung mot domain duy nhat: trang user o `/`, admin quan ly node o `/admin`.

- `domain.com`: portal cho user het han
- `domain.com/admin`: admin them/sua/xoa node WireGuard

## Cai dat 1 lenh

Tren Ubuntu server portal, chay:

```bash
curl -fsSL https://raw.githubusercontent.com/nguentb/wg-captive-portal/main/scripts/install-remote.sh | sudo bash -s -- --domain domain.com
```

Neu muon dat mat khau admin san:

```bash
curl -fsSL https://raw.githubusercontent.com/nguentb/wg-captive-portal/main/scripts/install-remote.sh | sudo bash -s -- --domain domain.com --admin-password 'your-strong-password'
```

Script se cai `nginx`, `nodejs`, tai repo ve `/opt/wg-captive-portal`, tao systemd service, cau hinh nginx reverse proxy HTTP, cai san cac lenh `ssl-install`, `portal-update`, `portal-uninstall` va in ra mat khau admin neu duoc tao tu dong.

## Cai SSL thu cong

Sau khi DNS da tro ve server portal, chay tren server:

```bash
sudo ssl-install
```

Lenh nay se hoi lan luot:

```text
Portal domain: domain.com
Let's Encrypt email: admin@domain.com
Cloudflare API token: token co quyen Zone DNS Edit voi zone domain.com
```

`ssl-install` se tu cai cac goi can thiet (`certbot`, `python3-certbot-dns-cloudflare`), ghi Cloudflare credentials vao `/etc/letsencrypt/wg-captive-cloudflare.ini` voi mode `0600`, cap cert cho domain portal, ghi lai nginx HTTPS config, test `nginx -t` va reload nginx. Admin se dung chung domain tai `/admin`.

Khi ghi nginx HTTPS config, HTTP port 80 duoc dat lam `default_server` va redirect co dinh ve domain portal da nhap. Cach nay tranh truong hop captive check gui Host nhu `connectivitycheck.gstatic.com` roi bi redirect nham sang HTTPS cua domain do.

Co the chay khong can hoi tuong tac:

```bash
sudo ssl-install --domain domain.com --email admin@domain.com --cloudflare-token 'your-cloudflare-token'
```

Neu muon test Let's Encrypt staging truoc:

```bash
sudo ssl-install --domain domain.com --email admin@domain.com --cloudflare-token 'your-cloudflare-token' --staging
```

## Update bang CLI

Sau khi da cai portal, update len ban moi nhat bang:

```bash
sudo portal-update
```

Neu muon update tu branch hoac repo khac:

```bash
sudo portal-update --branch main --repo nguentb/wg-captive-portal
```

`portal-update` se tai source moi, cap nhat file app, cap nhat cac CLI script, cap nhat systemd unit va restart service. Script khong ghi de nginx HTTPS dang co, de tranh lam mat cau hinh SSL hien tai. Neu nginx site bi mat, co the tao lai HTTP config bang:

```bash
sudo portal-update --domain domain.com
```

## Uninstall bang CLI

Go portal khoi server:

```bash
sudo portal-uninstall
```

Mac dinh lenh nay go service, nginx site, file app va cac CLI command, nhung giu lai data node va SSL/cert.

Xoa ca data node:

```bash
sudo portal-uninstall --purge-data
```

Xoa ca SSL/cert va Cloudflare credentials:

```bash
sudo portal-uninstall --purge-ssl --domain domain.com
```

Neu muon chay khong hoi xac nhan:

```bash
sudo portal-uninstall --yes
```

## Cai service Node

```bash
sudo mkdir -p /opt/wg-captive-portal
sudo cp index.html server.js package.json /opt/wg-captive-portal/
sudo cp scripts/ssl-install.sh /usr/local/sbin/ssl-install
sudo cp scripts/portal-update.sh /usr/local/sbin/portal-update
sudo cp scripts/portal-uninstall.sh /usr/local/sbin/portal-uninstall
sudo chmod +x /usr/local/sbin/ssl-install /usr/local/sbin/portal-update /usr/local/sbin/portal-uninstall
sudo cp systemd/wg-captive-portal.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now wg-captive-portal
```

Mac dinh systemd trong repo de Node nghe noi bo `127.0.0.1:8080`; nginx se public port 80/443 va proxy vao Node. Nen doi mat khau admin truoc khi public:

```bash
sudo systemctl edit wg-captive-portal
```

Them:

```ini
[Service]
Environment=ADMIN_PASSWORD=your-strong-password
Environment=NODE_STORE=/etc/wg-captive-portal-nodes.json
```

Sau do:

```bash
sudo systemctl daemon-reload
sudo systemctl restart wg-captive-portal
```

## Chay sau nginx

Neu dung nginx/SSL, nen cho Node nghe local port, vi nginx nghe 80/443:

```ini
[Service]
Environment=HOST=127.0.0.1
Environment=PORT=8080
Environment=ADMIN_PASSWORD=your-strong-password
Environment=NODE_STORE=/etc/wg-captive-portal-nodes.json
```

Copy nginx reverse proxy:

```bash
sudo cp nginx.conf /etc/nginx/sites-available/wg-captive-portal
sudo ln -s /etc/nginx/sites-available/wg-captive-portal /etc/nginx/sites-enabled/wg-captive-portal
sudo nginx -t
sudo systemctl reload nginx
```

DNS tro ve IP portal:

```text
domain.com  A  PORTAL_SERVER_IP
```

## Chay Node truc tiep khong nginx

Neu khong dung nginx, override service de Node nghe public port 80:

```ini
[Service]
Environment=HOST=0.0.0.0
Environment=PORT=80
Environment=ADMIN_PASSWORD=your-strong-password
```

## Admin node

Vao:

```text
https://domain.com/admin
```

Them node gom:

```text
Server name: wg-server-01
Node API address: https://wg.example.com:51822
API token: wgc_xxxxxxxxxxxxxxxxxxxxx
```

Token duoc luu o server portal va khong hien day du tren trinh duyet.

## Portal user

Portal nhan link dang:

```text
https://domain.com/?node=wg-server-01&ip=10.8.0.2
```

Trang se goi backend portal:

```text
GET /api/client-info?node=wg-server-01&ip=10.8.0.2
```

Backend portal se doc danh sach node da cau hinh trong admin, goi API node WireGuard, lay ten user/trang thai/han dung, roi tra ve cho giao dien portal.

## Cau hinh bang env neu khong dung admin

Van co the cau hinh mot node bang env:

```ini
Environment=NODE_NAME=wg-server-01
Environment=NODE_API_BASE=https://wg.example.com:51822
Environment=NODE_API_TOKEN=wgc_xxxxxxxxxxxxxxxxxxxxx
```

Hoac nhieu node bang JSON:

```ini
Environment='NODE_API_CONFIG={"wg-server-01":{"baseUrl":"https://wg1.example.com:51822","token":"wgc_token_1"},"wg-server-02":{"baseUrl":"https://wg2.example.com:51822","token":"wgc_token_2"}}'
```

Node trong admin se uu tien hon env neu trung server name.

## Kiem tra

```bash
curl -i http://domain.com/
curl -i http://domain.com/?node=wg-server-01\&ip=10.8.0.2
curl -i http://domain.com/admin
```

Moi URL HTTP tren domain portal deu nen tra ve trang `VPN het han`, tru `/admin` se vao admin.
