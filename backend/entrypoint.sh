#!/bin/sh
set -e

# =============================================================================
# Mwamba Taxi — Entrypoint intelligent
# Gère : wait_for_db, migrations, collectstatic, puis démarrage Daphne/Celery
# =============================================================================

echo "╔═══════════════════════════════════════════════════╗"
echo "║         🚕 Mwamba Taxi — Démarrage               ║"
echo "╚═══════════════════════════════════════════════════╝"

# ─── 1. Attendre que PostgreSQL soit prêt ─────────────────────────────
echo "⏳ Attente de la base de données..."
MAX_RETRIES=30
RETRY=0
while ! python manage.py wait_for_db 2>/dev/null; do
  RETRY=$((RETRY + 1))
  if [ "$RETRY" -ge "$MAX_RETRIES" ]; then
    echo "❌ Base de données non disponible après ${MAX_RETRIES} tentatives."
    exit 1
  fi
  echo "   ↻ Tentative $RETRY/$MAX_RETRIES..."
  sleep 2
done
echo "✅ Base de données prête."

# ─── 2. Migrations ───────────────────────────────────────────────────
if [ "${SKIP_MIGRATIONS}" != "true" ]; then
  echo "📦 Migrations..."
  python manage.py migrate --noinput
  echo "✅ Migrations appliquées."
else
  echo "⏭️  Migrations ignorées (SKIP_MIGRATIONS=true)."
fi

# ─── 3. Fichiers statiques ──────────────────────────────────────────
if [ "${SKIP_COLLECTSTATIC}" != "true" ]; then
  echo "📁 Collecte des fichiers statiques..."
  python manage.py collectstatic --noinput --clear 2>/dev/null || python manage.py collectstatic --noinput
  echo "✅ Fichiers statiques collectés."
else
  echo "⏭️  Collectstatic ignoré (SKIP_COLLECTSTATIC=true)."
fi

# ─── 4. Créer un superuser si demandé ───────────────────────────────
if [ -n "${DJANGO_SUPERUSER_PHONE}" ]; then
  echo "👤 Vérification du superuser..."
  python manage.py shell -c "
from apps.accounts.models import User
if not User.objects.filter(phone_number='${DJANGO_SUPERUSER_PHONE}').exists():
    User.objects.create_superuser(phone_number='${DJANGO_SUPERUSER_PHONE}', password='${DJANGO_SUPERUSER_PASSWORD:-admin123}')
    print('   ✅ Superuser créé.')
else:
    print('   ℹ️  Superuser existe déjà.')
" 2>/dev/null || echo "   ⚠️  Création superuser ignorée."
fi

# ─── 5. Démarrage ───────────────────────────────────────────────────
if [ $# -gt 0 ]; then
  echo "🚀 Commande personnalisée: $@"
  exec "$@"
else
  echo "🚀 Démarrage de Daphne (ASGI)..."
  echo "   ↳ 0.0.0.0:8000"
  exec daphne \
    -b 0.0.0.0 \
    -p 8000 \
    --access-log - \
    --proxy-headers \
    config.asgi:application
fi
