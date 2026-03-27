#!/bin/sh
set -e

echo "==> Attente de la base de données..."
python manage.py wait_for_db 2>/dev/null || sleep 5

echo "==> Application des migrations..."
python manage.py migrate --noinput

echo "==> Collecte des fichiers statiques..."
python manage.py collectstatic --noinput

if [ $# -gt 0 ]; then
  echo "==> Démarrage commande personnalisée: $@"
  exec "$@"
else
  echo "==> Démarrage de Daphne..."
  exec daphne -b 0.0.0.0 -p 8000 config.asgi:application
fi
