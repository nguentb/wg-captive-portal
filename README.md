# wg-captive-portal

Web HTTP/HTTPS rieng cho captive portal. Repo nay chi hien thi trang thong bao mac dinh cho user bi captive; khong co trang admin va khong luu thong tin node/user.

- `domain.com`: portal thong bao VPN het han
- HTTP port 80 duoc nginx redirect sang HTTPS cua domain portal
- Moi duong dan public deu tra ve cung mot trang portal mac dinh

## Cai dat 1 lenh

Tren Ubuntu server portal, chay:

```bash
curl -fsSL https://raw.githubusercontent.com/nguentb/wg-captive-portal/main/scripts/install-remote.sh | sudo bash -s -- --domain domain.com
```

Script se cai `nginx`, `nodejs`, tai repo ve `/opt/wg-captive-portal`, tao systemd service, cau hinh nginx reverse proxy HTTP, cai san cac lenh `ssl-install`, `portal-update`, `portal-uninstall`.

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

`ssl-install` se tu cai cac goi can thiet (`certbot`, `python3-certbot-dns-cloudflare`), ghi Cloudflare credentials vao `/etc/letsencrypt/wg-captive-cloudflare.ini` voi mode `0600`, cap cert cho domain portal, ghi lai nginx HTTPS config, test `nginx -t` va reload nginx.

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
sudo systemctl restart wg-captive-portal
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

Xoa ca SSL/cert va Cloudflare credentials:

```bash
sudo portal-uninstall --purge-ssl --domain domain.com
```

Neu muon chay khong hoi xac nhan:

```bash
sudo portal-uninstall --yes
```

## Cai service Node thu cong

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

Mac dinh systemd trong repo de Node nghe noi bo `127.0.0.1:8080`; nginx se public port 80/443 va proxy vao Node.

## Chay sau nginx

Neu dung nginx/SSL, nen cho Node nghe local port, vi nginx nghe 80/443:

```ini
[Service]
Environment=HOST=127.0.0.1
Environment=PORT=8080
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
```

## Portal user

Trang user o `/` chi hien thi thong bao mac dinh qua HTTPS. Node captive chi can dua user den domain portal; portal khong hien ten user, IP noi bo hay trang thai rieng tren giao dien user.

## Kiem tra

```bash
curl -i http://domain.com/
curl -i https://domain.com/
```

Moi URL public tren domain portal deu nen tra ve trang `VPN het han`.
