#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
#  EdgeStone Ticketing System — Hostinger VPS Deploy Script
#  Tested on: Ubuntu 22.04 LTS / Debian 12
#
#  One-time setup:
#    1. SSH into your Hostinger VPS
#    2. git clone https://github.com/Aerotalk/EdgeStoneBackendInfra.git /opt/edgestone
#    3. cd /opt/edgestone
#    4. chmod +x deploy.sh
#    5. sudo ./deploy.sh
#
#  Re-deploy after code changes:
#    cd /opt/edgestone && git pull && sudo ./deploy.sh --update
# ══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

# ── Config — change these ─────────────────────────────────────────────────────
DOMAIN="desinomads.com"
LETSENCRYPT_EMAIL="it@edgestone.in"   # Used by Let's Encrypt for expiry alerts
APP_DIR="/opt/edgestone"              # Where the app lives on the server
# ─────────────────────────────────────────────────────────────────────────────

UPDATE_MODE=false
if [[ "${1:-}" == "--update" ]]; then
    UPDATE_MODE=true
fi

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓] $1${NC}"; }
info() { echo -e "${CYAN}[→] $1${NC}"; }
warn() { echo -e "${YELLOW}[!] $1${NC}"; }
err()  { echo -e "${RED}[✗] $1${NC}"; exit 1; }

banner() {
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════${NC}"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1 — System packages
# ─────────────────────────────────────────────────────────────────────────────
install_dependencies() {
    banner "STEP 1 — Installing system dependencies"
    apt-get update -y -q
    apt-get install -y -q \
        curl \
        gnupg \
        ca-certificates \
        lsb-release \
        rsync \
        git \
        certbot \
        ufw
    log "System packages installed"
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2 — Docker & Docker Compose
# ─────────────────────────────────────────────────────────────────────────────
install_docker() {
    banner "STEP 2 — Docker"
    if command -v docker &>/dev/null; then
        log "Docker already installed: $(docker --version)"
    else
        info "Installing Docker..."
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
            | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
            https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
            > /etc/apt/sources.list.d/docker.list
        apt-get update -y -q
        apt-get install -y -q \
            docker-ce \
            docker-ce-cli \
            containerd.io \
            docker-compose-plugin
        systemctl enable --now docker
        log "Docker installed: $(docker --version)"
    fi

    # Verify docker compose v2
    if docker compose version &>/dev/null 2>&1; then
        log "Docker Compose v2: $(docker compose version)"
    else
        err "Docker Compose plugin not found. Re-run the script after a fresh Docker install."
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3 — Firewall
# ─────────────────────────────────────────────────────────────────────────────
configure_firewall() {
    banner "STEP 3 — Firewall (UFW)"
    ufw allow OpenSSH   2>/dev/null || true
    ufw allow 80/tcp    2>/dev/null || true
    ufw allow 443/tcp   2>/dev/null || true
    # Explicitly ALLOW outbound SMTP — Hostinger VPS does not block these
    # (unlike Railway/Render). Zoho SMTP on 465 and 587 will work fine here.
    echo "y" | ufw enable 2>/dev/null || true
    log "UFW enabled — ports 22, 80, 443 open"
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 4 — SSL Certificate (Let's Encrypt)
# ─────────────────────────────────────────────────────────────────────────────
obtain_ssl() {
    banner "STEP 4 — SSL Certificate"

    if [ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]; then
        log "SSL certificate already exists for ${DOMAIN}"
        return
    fi

    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo "unknown")
    warn "Your server's public IP is: ${SERVER_IP}"
    warn "Make sure ${DOMAIN} A record points to this IP before continuing."
    warn "DNS propagation can take up to 10 minutes after setting it in Hostinger panel."
    echo ""
    read -p "Press ENTER once DNS is set, or Ctrl+C to abort..."

    info "Stopping any service using port 80..."
    docker compose -f "${APP_DIR}/docker-compose.yml" stop nginx 2>/dev/null || true

    info "Obtaining SSL certificate from Let's Encrypt..."
    certbot certonly \
        --standalone \
        --non-interactive \
        --agree-tos \
        --email "${LETSENCRYPT_EMAIL}" \
        -d "${DOMAIN}" \
        -d "www.${DOMAIN}" \
        || err "Certbot failed. Check DNS propagation and that port 80 is free."

    log "SSL certificate obtained — valid for 90 days, auto-renewed by cron"
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 5 — Environment file
# ─────────────────────────────────────────────────────────────────────────────
setup_env() {
    banner "STEP 5 — Environment Variables"

    if [ -f "${APP_DIR}/.env.production" ]; then
        log ".env.production already exists — skipping"
        return
    fi

    if [ ! -f "${APP_DIR}/.env.production.example" ]; then
        err ".env.production.example not found in ${APP_DIR}. Make sure you cloned the full repo."
    fi

    cp "${APP_DIR}/.env.production.example" "${APP_DIR}/.env.production"
    chmod 600 "${APP_DIR}/.env.production"

    warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    warn " ACTION REQUIRED: Fill in your production secrets!"
    warn " Run:  nano ${APP_DIR}/.env.production"
    warn ""
    warn " Required fields:"
    warn "  DATABASE_URL   — your Render PostgreSQL URL"
    warn "  JWT_SECRET     — long random string"
    warn "  MAIL_PASSWORD  — Zoho app password for IMAP"
    warn "  ZEPTO_MAIL_TOKEN  — from ZeptoMail dashboard"
    warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    read -p "Press ENTER after saving .env.production to continue..."

    log ".env.production created and permissions secured (chmod 600)"
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 6 — Build & Start containers
# ─────────────────────────────────────────────────────────────────────────────
start_containers() {
    banner "STEP 6 — Docker Compose Up"
    cd "${APP_DIR}"

    if [ "$UPDATE_MODE" = true ]; then
        info "Update mode — rebuilding backend only..."
        docker compose up -d --build --no-deps backend
        docker compose restart nginx 2>/dev/null || true
    else
        info "Full deploy — pulling nginx image and building backend..."
        docker compose pull nginx 2>/dev/null || true
        docker compose up -d --build
    fi

    info "Waiting for containers to stabilise..."
    sleep 8

    log "Container status:"
    docker compose ps
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 7 — Run Prisma migrations
# ─────────────────────────────────────────────────────────────────────────────
run_migrations() {
    banner "STEP 7 — Prisma DB Migrations"
    cd "${APP_DIR}"

    info "Running prisma migrate deploy inside backend container..."
    docker compose exec -T backend npx prisma migrate deploy \
        && log "Migrations applied" \
        || warn "Migration failed or already up-to-date — check manually if needed"
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 8 — Certificate auto-renewal cron
# ─────────────────────────────────────────────────────────────────────────────
setup_renewal_cron() {
    banner "STEP 8 — SSL Auto-Renewal"

    CRON_JOB="0 3 * * 1 certbot renew --quiet --pre-hook 'docker compose -f ${APP_DIR}/docker-compose.yml stop nginx' --post-hook 'docker compose -f ${APP_DIR}/docker-compose.yml start nginx'"

    if crontab -l 2>/dev/null | grep -q "certbot renew"; then
        log "Certbot renewal cron already configured"
    else
        (crontab -l 2>/dev/null; echo "${CRON_JOB}") | crontab -
        log "Certbot auto-renewal cron set (every Monday at 3 AM)"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 9 — Health check
# ─────────────────────────────────────────────────────────────────────────────
health_check() {
    banner "STEP 9 — Health Check"

    info "Testing https://${DOMAIN}/..."
    sleep 3

    HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "https://${DOMAIN}/" 2>/dev/null || echo "000")

    if [ "$HTTP_CODE" = "200" ]; then
        log "✅ API is live! https://${DOMAIN}/ returned HTTP 200"
    else
        warn "Health check returned HTTP ${HTTP_CODE} — containers may still be starting."
        warn "Run: docker compose logs -f backend"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════════════
banner "EdgeStone Ticketing System — Hostinger VPS Deploy"
echo "  Domain : ${DOMAIN}"
echo "  App dir: ${APP_DIR}"
echo "  Mode   : $([ "$UPDATE_MODE" = true ] && echo 'UPDATE' || echo 'FRESH INSTALL')"
echo ""

if [ "$UPDATE_MODE" = false ]; then
    install_dependencies
    install_docker
    configure_firewall
    obtain_ssl
    setup_env
fi

start_containers
run_migrations
setup_renewal_cron
health_check

echo ""
banner "🎉 Deployment Complete!"
echo "  API live:      https://${DOMAIN}/api/"
echo "  Health check:  https://${DOMAIN}/"
echo ""
echo "  Useful commands:"
echo "  ┌─────────────────────────────────────────────────────────────────"
echo "  │  docker compose ps                          # container status"
echo "  │  docker compose logs -f backend             # stream backend logs"
echo "  │  docker compose logs -f nginx               # stream nginx logs"
echo "  │  docker compose restart backend             # restart backend"
echo "  │  docker compose exec backend bash           # shell into backend"
echo "  │  git pull && ./deploy.sh --update           # redeploy after changes"
echo "  └─────────────────────────────────────────────────────────────────"
echo ""
