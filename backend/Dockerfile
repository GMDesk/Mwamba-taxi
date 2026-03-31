###############################################################################
# Mwamba Taxi — Dockerfile Multi-Stage Production
# Stage 1: Builder (installe les dépendances Python)
# Stage 2: Runtime (image finale minimale)
###############################################################################

# ─────────────── Stage 1 : Builder ───────────────
FROM python:3.12-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /build

RUN apt-get update && \
    apt-get install -y --no-install-recommends gcc libpq-dev && \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --prefix=/install -r requirements.txt


# ─────────────── Stage 2 : Runtime ───────────────
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DJANGO_SETTINGS_MODULE=config.settings

WORKDIR /app

# Dépendances système minimales (runtime uniquement, pas de gcc)
RUN apt-get update && \
    apt-get install -y --no-install-recommends libpq5 curl && \
    rm -rf /var/lib/apt/lists/*

# Copier les packages Python depuis le builder
COPY --from=builder /install /usr/local

# Créer un utilisateur non-root pour la sécurité
RUN groupadd -r mwamba && useradd -r -g mwamba -d /app -s /sbin/nologin mwamba

# Copier le code source
COPY . .
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Créer les dossiers pour static/media et donner les permissions
RUN mkdir -p /app/staticfiles /app/media && \
    chown -R mwamba:mwamba /app

USER mwamba

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -sf http://localhost:8000/api/health/ || exit 1

ENTRYPOINT ["/entrypoint.sh"]
