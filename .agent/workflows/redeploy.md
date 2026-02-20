---
description: Redeploy EdgeStone backend to Hostinger VPS after code changes
---

## Redeploy to Hostinger VPS

Use this when you've pushed code changes and want to re-deploy.

### Option A — Automatic (GitHub Actions)
Just push to `main`. The GitHub Actions workflow at `.github/workflows/deploy.yml` will:
1. SSH into the VPS
2. Run `git pull`
3. Run `./deploy.sh --update`
4. Health-check `https://desinomads.com/`

### Option B — Manual SSH
```bash
ssh root@YOUR_VPS_IP
cd /opt/edgestone
git pull origin main
./deploy.sh --update
```

### Watch logs after deploy
```bash
docker compose logs -f backend
```

### If backend container is stuck / crashed
```bash
docker compose restart backend
docker compose logs --tail=50 backend
```

### Full reset (last resort)
```bash
docker compose down
docker compose up -d --build
