# SSL Certificate Setup — `*.etl.cnxkit.com`

Wildcard certificates **require the DNS-01 challenge** — HTTP file-based challenges cannot
issue wildcards. This means certbot must prove you control the domain by creating a
`_acme-challenge.etl.cnxkit.com` TXT record.

Two paths are covered below:

- **Path A — Manual DNS** — Works with any DNS provider. Requires human intervention
  at renewal time (~every 90 days). Use this to get started quickly.
- **Path B — Automated DNS via API** — Enables true unattended renewal. Requires a
  certbot DNS plugin supported by your provider.

---

## Prerequisites

- Debian/Ubuntu-based system (adjust package commands for other distros)
- Root or sudo access
- `cnxkit.com` already pointing to this machine
- Port 80/443 open in firewall (only 443 needed long-term; 80 for ACME HTTP redirect)

---

## Step 1 — Install Certbot

```bash
sudo apt update
sudo apt install -y certbot
```

> If you later choose Path B, install the matching DNS plugin package at this point
> (e.g. `python3-certbot-dns-cloudflare`). See Path B section for details.

---

## Step 2 — Obtain the Wildcard Certificate (Path A — Manual DNS)

```bash
sudo certbot certonly \
  --manual \
  --preferred-challenges dns \
  -d "*.etl.cnxkit.com" \
  -d "etl.cnxkit.com" \
  --agree-tos \
  --email you@example.com
```

Both `*.etl.cnxkit.com` (covers subdomains) and bare `etl.cnxkit.com` are included
because wildcards do **not** cover the apex domain.

Certbot will pause and display something like:

```
Please deploy a DNS TXT record under the name:
_acme-challenge.etl.cnxkit.com

with the following value:
AbCdEfGhIjKlMnOpQrStUvWxYz1234567890abcde

Once deployed, press Enter to continue.
```

1. Log in to your DNS provider's dashboard.
2. Create a **TXT record**:
   - Name/Host: `_acme-challenge.etl` (or `_acme-challenge.etl.cnxkit.com` — your
     provider will tell you which format)
   - Value: the string certbot displayed
   - TTL: 60 (low TTL so the record propagates quickly)
3. Verify propagation before pressing Enter:
   ```bash
   dig TXT _acme-challenge.etl.cnxkit.com +short
   ```
   Wait until the value you entered appears in the output.
4. Press Enter in the certbot prompt.

On success, certificates are written to:

```
/etc/letsencrypt/live/etl.cnxkit.com/fullchain.pem   # cert + intermediates
/etc/letsencrypt/live/etl.cnxkit.com/privkey.pem      # private key
```

---

## Step 3 — Configure the Web Server

### Option A — Nginx (recommended reverse proxy in front of Rails)

Install nginx if not present:

```bash
sudo apt install -y nginx
```

Create `/etc/nginx/sites-available/etl`:

```nginx
server {
    listen 80;
    server_name *.etl.cnxkit.com etl.cnxkit.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name *.etl.cnxkit.com etl.cnxkit.com;

    ssl_certificate     /etc/letsencrypt/live/etl.cnxkit.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/etl.cnxkit.com/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    location / {
        proxy_pass         http://127.0.0.1:3000;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto https;
    }
}
```

Enable and test:

```bash
sudo ln -s /etc/nginx/sites-available/etl /etc/nginx/sites-enabled/etl
sudo nginx -t
sudo systemctl reload nginx
```

### Option B — Direct Rails with SSL (Puma)

If you want Puma to terminate SSL directly (no nginx), add to `config/puma.rb`:

```ruby
ssl_bind '0.0.0.0', '443',
  cert: '/etc/letsencrypt/live/etl.cnxkit.com/fullchain.pem',
  key:  '/etc/letsencrypt/live/etl.cnxkit.com/privkey.pem'
```

The Rails process will need read access to the Let's Encrypt directory:

```bash
sudo chmod 0755 /etc/letsencrypt/live /etc/letsencrypt/archive
sudo chmod 0644 /etc/letsencrypt/archive/etl.cnxkit.com/*.pem
```

---

## Step 4 — Auto-Renewal

### Path A — Manual renewal (reminder-based)

Let's Encrypt certificates expire after 90 days. With manual DNS, certbot cannot renew
automatically. Set a reminder and re-run the Step 2 command ~2 weeks before expiry.

Check current expiry at any time:

```bash
sudo certbot certificates
```

You will need to update the `_acme-challenge` TXT record again at each renewal.

---

### Path B — True Unattended Auto-Renewal (DNS API plugin)

This is strongly recommended for production. The process:

1. Install the certbot plugin for your DNS provider. Common examples:

   | Provider      | Package                              | Docs URL                                         |
   |---------------|--------------------------------------|--------------------------------------------------|
   | Cloudflare    | `python3-certbot-dns-cloudflare`     | https://certbot-dns-cloudflare.readthedocs.io    |
   | Route 53      | `python3-certbot-dns-route53`        | https://certbot-dns-route53.readthedocs.io       |
   | DigitalOcean  | `python3-certbot-dns-digitalocean`   | https://certbot-dns-digitalocean.readthedocs.io  |
   | Namecheap*    | manual hook script                   | https://github.com/alandoyle/letsencrypt-namecheap |

   \* Namecheap does not have an official certbot plugin; a hook script approach is needed.

2. Create a credentials file (example for Cloudflare):

   ```bash
   sudo mkdir -p /etc/letsencrypt/credentials
   sudo tee /etc/letsencrypt/credentials/cloudflare.ini > /dev/null <<'EOF'
   dns_cloudflare_api_token = YOUR_API_TOKEN_HERE
   EOF
   sudo chmod 600 /etc/letsencrypt/credentials/cloudflare.ini
   ```

3. Re-issue the certificate using the plugin:

   ```bash
   sudo certbot certonly \
     --dns-cloudflare \
     --dns-cloudflare-credentials /etc/letsencrypt/credentials/cloudflare.ini \
     -d "*.etl.cnxkit.com" \
     -d "etl.cnxkit.com" \
     --agree-tos \
     --email you@example.com \
     --force-renewal
   ```

   Replace `--dns-cloudflare` and the credentials flag with your provider's equivalents.

---

## Step 5 — Deploy Hook (reload server after renewal)

Create a hook so nginx (or puma) reloads the new certificate after every renewal:

```bash
sudo tee /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh > /dev/null <<'EOF'
#!/bin/bash
systemctl reload nginx
EOF
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
```

If using Puma directly instead of nginx, replace `systemctl reload nginx` with
`systemctl restart etl_server`.

---

## Step 6 — Verify Auto-Renewal Timer

Certbot installs a systemd timer on Debian/Ubuntu automatically. Confirm it is active:

```bash
systemctl status certbot.timer
```

You should see `active (waiting)`. The timer runs twice daily and renews any certificate
within 30 days of expiry.

Perform a dry run to confirm everything works end-to-end:

```bash
sudo certbot renew --dry-run
```

---

## Verification Checklist

```bash
# Certificate details
sudo certbot certificates

# TLS handshake check
openssl s_client -connect etl.cnxkit.com:443 -servername etl.cnxkit.com \
  </dev/null 2>/dev/null | openssl x509 -noout -text | grep -A2 "Subject Alternative"

# Quick curl check
curl -I https://etl.cnxkit.com/up
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `DNS problem: NXDOMAIN` | TXT record not propagated | Wait 30–120 s and retry; lower TTL next time |
| `Permission denied` reading cert | Rails/puma can't read `/etc/letsencrypt` | Run `chmod` from Step 3 Option B |
| `certbot renew` fails silently | Auto-renewal still requires DNS plugin | Switch to Path B or renew manually |
| Certificate shows old expiry after renewal | Deploy hook not running | Check `/etc/letsencrypt/renewal-hooks/deploy/` |
| nginx `unknown directive ssl` | `ngx_http_ssl_module` not compiled in | Install `nginx-full` instead of `nginx-light` |
