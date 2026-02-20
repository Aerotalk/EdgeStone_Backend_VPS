# EdgeStone — Hostinger VPS Deployment Guide

## Prerequisites
- Hostinger KVM VPS with Ubuntu 22.04 LTS
- Domain `desinomads.com` with DNS A record → your VPS IP
- SSH access to the VPS

---

## One-Time Fresh Deploy

### 1. SSH into your VPS
```bash
ssh root@YOUR_VPS_IP
```

### 2. Clone the repo
```bash
git clone https://github.com/Aerotalk/EdgeStoneBackendInfra.git /opt/edgestone
cd /opt/edgestone
chmod +x deploy.sh
```

### 3. Run the deploy script
```bash
sudo ./deploy.sh
```

The script will:
1. Install Docker, Docker Compose, Certbot, UFW
2. Configure firewall (ports 22, 80, 443)
3. Get a Let's Encrypt SSL cert for `desinomads.com`
4. Prompt you to fill in `.env.production`
5. Build and start backend + nginx containers
6. Run Prisma DB migrations
7. Set up SSL auto-renewal cron

---

## Fill in `.env.production` (Step 5 of deploy)

When prompted, run:
```bash
nano /opt/edgestone/.env.production
```

Fill in these values:

| Variable | Where to get it |
|----------|----------------|
| `DATABASE_URL` | Render dashboard → your PostgreSQL database |
| `JWT_SECRET` | Any long random string (32+ chars) |
| `MAIL_PASSWORD` | Zoho Mail → Settings → App Passwords |
| `ZEPTO_MAIL_TOKEN` | ZeptoMail dashboard → Mail Agents → API Token |
| `ZEPTO_FROM_EMAIL` | The sender address configured in your ZeptoMail Mail Agent |

Save with `Ctrl+O`, exit with `Ctrl+X`, then press ENTER to continue the script.

---

## Redeploy After Code Changes

```bash
cd /opt/edgestone
git pull
./deploy.sh --update
```

This rebuilds only the backend container — nginx stays up, zero downtime.

---

## Useful Commands

```bash
# Check container status
docker compose ps

# Stream live backend logs
docker compose logs -f backend

# Stream nginx logs
docker compose logs -f nginx

# Restart backend
docker compose restart backend

# Open shell in backend
docker compose exec backend bash

# Run a Prisma command
docker compose exec backend npx prisma studio
```

---

## Why Hostinger Works (vs Railway/Render)

| | Hostinger VPS | Railway / Render |
|--|--|--|
| SMTP port 465 | ✅ Open | ❌ Blocked |
| SMTP port 587 | ✅ Open | ❌ Blocked |
| Custom Nginx | ✅ | ❌ |
| Root access | ✅ | ❌ |

> **Email setup:** Both ZeptoMail (HTTP API) and Zoho SMTP work on Hostinger.
> `EMAIL_PROVIDER=zepto` is the default — reliable, fast, no port restrictions.
