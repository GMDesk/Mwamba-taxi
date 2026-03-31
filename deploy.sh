#!/bin/bash
set -e

# =============================================================================
# Mwamba Taxi — Script de Déploiement Intelligent
# Serveur: GCP europe-west1-b | Domaine: mwambataxi.com
#
# Usage:
#   ./deploy.sh              → Déploiement complet (build + up)
#   ./deploy.sh --quick      → Redémarrage rapide (sans rebuild)
#   ./deploy.sh --migrate    → Migrations seulement
#   ./deploy.sh --ssl-init   → Première installation SSL Let's Encrypt
#   ./deploy.sh --backup     → Backup base de données
#   ./deploy.sh --logs       → Voir les logs en temps réel
#   ./deploy.sh --status     → Status des services
#   ./deploy.sh --rollback   → Rollback au commit précédent
# =============================================================================

COMPOSE="docker compose -f docker-compose.yml -f docker-compose.production.yml"
DOMAIN="mwambataxi.com"
EMAIL="contact@mwambataxi.com"
BACKUP_DIR="./backups"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()   { echo -e "${GREEN}[DEPLOY]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ─── Vérifications préalables ────────────────────────────────────────
check_env() {
    if [ ! -f ./backend/.env.production ]; then
        error "Fichier ./backend/.env.production manquant!"
    fi
    if [ ! -f ./backend/firebase-key.json ]; then
        warn "firebase-key.json manquant — les notifications push ne fonctionneront pas."
    fi
}

# ─── Déploiement complet ────────────────────────────────────────────
deploy_full() {
    log "╔═══════════════════════════════════════════════════╗"
    log "║       🚕 Mwamba Taxi — Déploiement Production    ║"
    log "╚═══════════════════════════════════════════════════╝"

    check_env

    # Sauvegarder le commit actuel pour rollback
    git rev-parse HEAD > .last-deploy-commit 2>/dev/null || true

    log "📥 Récupération du code source..."
    git pull origin master --rebase || warn "Git pull échoué — on continue avec le code actuel."

    log "🏗️  Build des images Docker..."
    $COMPOSE build --no-cache backend

    log "🚀 Démarrage des services..."
    $COMPOSE up -d

    log "⏳ Attente du health check..."
    sleep 10
    check_health

    log "🧹 Nettoyage des images Docker inutilisées..."
    docker image prune -f 2>/dev/null || true

    log "✅ Déploiement terminé avec succès!"
    show_status
}

# ─── Redémarrage rapide (sans rebuild) ──────────────────────────────
deploy_quick() {
    log "⚡ Redémarrage rapide..."
    check_env
    git pull origin master --rebase || warn "Git pull échoué."
    $COMPOSE up -d --force-recreate
    sleep 8
    check_health
    log "✅ Redémarrage terminé!"
}

# ─── Migrations seulement ───────────────────────────────────────────
run_migrations() {
    log "📦 Application des migrations..."
    $COMPOSE exec backend python manage.py migrate --noinput
    log "✅ Migrations appliquées."
}

# ─── SSL Let's Encrypt (première fois) ──────────────────────────────
ssl_init() {
    log "🔐 Installation SSL Let's Encrypt pour $DOMAIN..."

    # Étape 1: Nginx en HTTP seulement (pour le challenge ACME)
    warn "Création d'un certificat temporaire auto-signé..."
    mkdir -p ./nginx/certs
    openssl req -x509 -nodes -days 1 -newkey rsa:2048 \
        -keyout ./nginx/certs/privkey.pem \
        -out ./nginx/certs/fullchain.pem \
        -subj "/CN=$DOMAIN" 2>/dev/null

    # Étape 2: Démarrer Nginx
    $COMPOSE up -d nginx

    # Étape 3: Obtenir le vrai certificat
    log "📜 Demande du certificat Let's Encrypt..."
    docker run --rm \
        -v /etc/letsencrypt:/etc/letsencrypt \
        -v certbot_www:/var/www/certbot \
        certbot/certbot certonly \
            --webroot \
            --webroot-path=/var/www/certbot \
            -d "$DOMAIN" \
            -d "www.$DOMAIN" \
            --email "$EMAIL" \
            --agree-tos \
            --no-eff-email

    # Étape 4: Redémarrer avec le vrai certificat
    log "🔄 Redémarrage Nginx avec le certificat Let's Encrypt..."
    $COMPOSE restart nginx

    log "✅ SSL configuré pour $DOMAIN!"
}

# ─── Backup base de données ─────────────────────────────────────────
backup_db() {
    mkdir -p "$BACKUP_DIR"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="$BACKUP_DIR/mwamba_taxi_$TIMESTAMP.sql.gz"

    log "💾 Backup de la base de données..."
    $COMPOSE exec -T db pg_dump -U mwamba mwamba_taxi | gzip > "$BACKUP_FILE"

    # Garder seulement les 10 derniers backups
    ls -t "$BACKUP_DIR"/mwamba_taxi_*.sql.gz 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null || true

    SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    log "✅ Backup sauvegardé: $BACKUP_FILE ($SIZE)"
}

# ─── Health check ───────────────────────────────────────────────────
check_health() {
    local retries=5
    local delay=3
    for i in $(seq 1 $retries); do
        if curl -sf http://localhost:8000/api/health/ > /dev/null 2>&1; then
            log "💚 Health check OK"
            return 0
        elif curl -sf https://$DOMAIN/api/health/ > /dev/null 2>&1; then
            log "💚 Health check OK (HTTPS)"
            return 0
        fi
        warn "Health check tentative $i/$retries..."
        sleep $delay
    done
    warn "⚠️  Health check échoué — vérifiez les logs: ./deploy.sh --logs"
    return 1
}

# ─── Status des services ────────────────────────────────────────────
show_status() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════ STATUS ═══════════════════════╗${NC}"
    $COMPOSE ps
    echo ""
    echo -e "${CYAN}─── Utilisation disque (volumes) ─────────────────────${NC}"
    docker system df 2>/dev/null | head -5
    echo -e "${CYAN}╚═════════════════════════════════════════════════════╝${NC}"
}

# ─── Logs en temps réel ─────────────────────────────────────────────
show_logs() {
    $COMPOSE logs -f --tail=100
}

# ─── Rollback ───────────────────────────────────────────────────────
rollback() {
    if [ ! -f .last-deploy-commit ]; then
        error "Pas de commit précédent enregistré pour rollback."
    fi
    PREV_COMMIT=$(cat .last-deploy-commit)
    log "🔙 Rollback vers le commit: $PREV_COMMIT"
    git checkout "$PREV_COMMIT"
    $COMPOSE build backend
    $COMPOSE up -d
    sleep 8
    check_health
    log "✅ Rollback terminé."
}

# ─── Main ───────────────────────────────────────────────────────────
case "${1:-}" in
    --quick)     deploy_quick ;;
    --migrate)   run_migrations ;;
    --ssl-init)  ssl_init ;;
    --backup)    backup_db ;;
    --logs)      show_logs ;;
    --status)    show_status ;;
    --rollback)  rollback ;;
    --health)    check_health ;;
    --help|-h)
        echo "Usage: ./deploy.sh [option]"
        echo ""
        echo "Options:"
        echo "  (aucune)     Déploiement complet (build + up)"
        echo "  --quick      Redémarrage rapide sans rebuild"
        echo "  --migrate    Migrations DB seulement"
        echo "  --ssl-init   Première installation SSL Let's Encrypt"
        echo "  --backup     Backup base de données"
        echo "  --logs       Logs en temps réel"
        echo "  --status     Status des services"
        echo "  --rollback   Retour au déploiement précédent"
        echo "  --health     Vérification health check"
        ;;
    *)           deploy_full ;;
esac
