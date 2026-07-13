# wg-captive-portal

Web HTTP/HTTPS rieng cho captive portal. Domain chinh hien trang het han, subdomain `adm.*` hien trang admin quan ly node.

- `domain.com`: portal cho user het han
- `adm.domain.com`: admin them/sua/xoa node WireGuard

## Cai service Node

```bash
sudo mkdir -p /opt/wg-captive-portal
sudo cp index.html server.js package.json /opt/wg-captive-portal/
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
Environment=ADMIN_HOST=adm.domain.com
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
Environment=ADMIN_HOST=adm.domain.com
Environment=NODE_STORE=/etc/wg-captive-portal-nodes.json
```

Copy nginx reverse proxy:

```bash
sudo cp nginx.conf /etc/nginx/sites-available/wg-captive-portal
sudo ln -s /etc/nginx/sites-available/wg-captive-portal /etc/nginx/sites-enabled/wg-captive-portal
sudo nginx -t
sudo systemctl reload nginx
```

DNS tro ve cung IP portal:

```text
domain.com      A  PORTAL_SERVER_IP
adm.domain.com  A  PORTAL_SERVER_IP
```


## Chay Node truc tiep khong nginx

Neu khong dung nginx, override service de Node nghe public port 80:

```ini
[Service]
Environment=HOST=0.0.0.0
Environment=PORT=80
Environment=ADMIN_HOST=adm.domain.com
Environment=ADMIN_PASSWORD=your-strong-password
```

## Admin node

Vao:

```text
https://adm.domain.com
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
curl -i http://adm.domain.com/
```

Moi URL HTTP tren domain portal deu nen tra ve trang `VPN het han`, tru `adm.*` se vao admin.
