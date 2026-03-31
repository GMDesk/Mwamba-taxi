# =============================================================================
# Mwamba Taxi — Makefile
# Commandes rapides pour le développement et la production
# =============================================================================

.PHONY: help dev prod stop logs status backup migrate shell test ssl-init clean

COMPOSE_DEV  = docker compose -f docker-compose.yml
COMPOSE_PROD = docker compose -f docker-compose.yml -f docker-compose.production.yml

# ─── Aide ────────────────────────────────────────────────────────────
help: ## Afficher cette aide
	@echo "╔═══════════════════════════════════════════════════╗"
	@echo "║         🚕 Mwamba Taxi — Commandes               ║"
	@echo "╚═══════════════════════════════════════════════════╝"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo ""

# ─── Développement local ────────────────────────────────────────────
dev: ## Démarrer en mode développement
	$(COMPOSE_DEV) up -d
	@echo "✅ Dev: http://localhost:8000"

dev-build: ## Build + démarrer en dev
	$(COMPOSE_DEV) up -d --build
	@echo "✅ Dev build: http://localhost:8000"

# ─── Production ─────────────────────────────────────────────────────
prod: ## Démarrer en mode production
	$(COMPOSE_PROD) up -d
	@echo "✅ Production: https://mwambataxi.com"

prod-build: ## Build + démarrer en production
	$(COMPOSE_PROD) up -d --build
	@echo "✅ Production build terminé"

deploy: ## Déploiement complet (script deploy.sh)
	bash deploy.sh

deploy-quick: ## Redémarrage rapide production
	bash deploy.sh --quick

# ─── Services ───────────────────────────────────────────────────────
stop: ## Arrêter tous les services
	$(COMPOSE_PROD) down 2>/dev/null || $(COMPOSE_DEV) down

restart: ## Redémarrer tous les services
	$(COMPOSE_PROD) restart 2>/dev/null || $(COMPOSE_DEV) restart

status: ## Status des services
	$(COMPOSE_PROD) ps 2>/dev/null || $(COMPOSE_DEV) ps

logs: ## Logs en temps réel (tous les services)
	$(COMPOSE_PROD) logs -f --tail=100 2>/dev/null || $(COMPOSE_DEV) logs -f --tail=100

logs-backend: ## Logs du backend seulement
	$(COMPOSE_PROD) logs -f --tail=200 backend 2>/dev/null || $(COMPOSE_DEV) logs -f --tail=200 backend

logs-celery: ## Logs Celery
	$(COMPOSE_PROD) logs -f --tail=100 celery_worker celery_beat

logs-nginx: ## Logs Nginx
	$(COMPOSE_PROD) logs -f --tail=100 nginx

# ─── Base de données ────────────────────────────────────────────────
migrate: ## Appliquer les migrations
	$(COMPOSE_PROD) exec backend python manage.py migrate --noinput 2>/dev/null || \
	$(COMPOSE_DEV) exec backend python manage.py migrate --noinput

makemigrations: ## Créer les migrations
	$(COMPOSE_PROD) exec backend python manage.py makemigrations 2>/dev/null || \
	$(COMPOSE_DEV) exec backend python manage.py makemigrations

backup: ## Backup de la base de données
	bash deploy.sh --backup

# ─── Shell & Debug ──────────────────────────────────────────────────
shell: ## Django shell interactif
	$(COMPOSE_PROD) exec backend python manage.py shell 2>/dev/null || \
	$(COMPOSE_DEV) exec backend python manage.py shell

bash: ## Bash dans le container backend
	$(COMPOSE_PROD) exec backend bash 2>/dev/null || \
	$(COMPOSE_DEV) exec backend bash

dbshell: ## Shell PostgreSQL
	$(COMPOSE_PROD) exec db psql -U mwamba mwamba_taxi 2>/dev/null || \
	$(COMPOSE_DEV) exec db psql -U mwamba mwamba_taxi

createsuperuser: ## Créer un superuser
	$(COMPOSE_PROD) exec backend python manage.py createsuperuser 2>/dev/null || \
	$(COMPOSE_DEV) exec backend python manage.py createsuperuser

# ─── SSL ────────────────────────────────────────────────────────────
ssl-init: ## Première installation SSL Let's Encrypt
	bash deploy.sh --ssl-init

ssl-renew: ## Forcer le renouvellement SSL
	$(COMPOSE_PROD) exec certbot certbot renew --force-renewal

# ─── Health check ───────────────────────────────────────────────────
health: ## Vérifier le health check
	@curl -sf http://localhost:8000/api/health/ && echo " ✅ OK" || echo " ❌ FAIL"

health-prod: ## Health check production
	@curl -sf https://mwambataxi.com/api/health/ && echo " ✅ OK" || echo " ❌ FAIL"

# ─── Nettoyage ──────────────────────────────────────────────────────
clean: ## Nettoyer les images Docker inutilisées
	docker image prune -f
	docker volume prune -f
	@echo "✅ Nettoyage terminé"

clean-all: ## ⚠️  Tout supprimer (volumes inclus)
	@echo "⚠️  Ceci va supprimer TOUTES les données (DB, media, etc.)"
	@read -p "Êtes-vous sûr? (oui/non) " confirm; \
	if [ "$$confirm" = "oui" ]; then \
		$(COMPOSE_PROD) down -v 2>/dev/null; \
		$(COMPOSE_DEV) down -v 2>/dev/null; \
		echo "✅ Tout supprimé"; \
	else \
		echo "❌ Annulé"; \
	fi

# ─── Tests ──────────────────────────────────────────────────────────
test: ## Lancer les tests Django
	$(COMPOSE_DEV) exec backend python manage.py test --verbosity=2

check: ## Django system check
	$(COMPOSE_PROD) exec backend python manage.py check --deploy 2>/dev/null || \
	$(COMPOSE_DEV) exec backend python manage.py check
