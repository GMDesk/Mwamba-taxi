# Mwamba Taxi — Plateforme de Transport à Kinshasa

Application complète de VTC (taxi) pour Kinshasa, RDC. Comprend un backend Django REST, une application passager Flutter et une application chauffeur Flutter.

## Architecture

```
Mwamba-taxi/
├── backend/              # Django REST API + WebSocket
│   ├── config/           # Settings, URLs, ASGI, Celery
│   └── apps/
│       ├── accounts/     # Authentification (JWT + OTP), Profils chauffeurs
│       ├── rides/        # Gestion des courses, tracking temps réel
│       ├── payments/     # Paiements Mobile Money (Maxicash)
│       ├── notifications/# Push (FCM) + SMS (Twilio)
│       ├── promotions/   # Codes promo, parrainage
│       ├── reviews/      # Notations chauffeurs
│       └── admin_dashboard/ # API tableau de bord admin
├── mobile/
│   ├── mwamba_taxi/      # App Flutter Passager
│   └── mwamba_driver/    # App Flutter Chauffeur
├── nginx/                # Configuration Nginx
├── docker-compose.yml    # Orchestration Docker
└── README.md
```

## Technologies

| Composant | Stack |
|-----------|-------|
| Backend | Django 5, DRF, Django Channels, Celery, PostgreSQL, Redis |
| Auth | JWT (SimpleJWT) + OTP par SMS (Twilio) |
| Paiements | Maxicash Mobile Money (CDF) |
| Notifications | Firebase Cloud Messaging + Twilio SMS |
| Mobile Passager | Flutter 3, BLoC, Google Maps, WebSocket |
| Mobile Chauffeur | Flutter 3, BLoC, Google Maps, Geolocator |
| Déploiement | Docker Compose, Nginx, Daphne (ASGI) |

## Démarrage rapide

### Backend (Docker)

```bash
# 1. Copier et configurer les variables d'environnement
cp backend/.env.example backend/.env
# Éditer backend/.env avec vos clés API

# 2. Lancer les services
docker compose up -d

# 3. Appliquer les migrations
docker compose exec backend python manage.py migrate

# 4. Créer un super-utilisateur
docker compose exec backend python manage.py createsuperuser
```

### Backend (Développement local)

```bash
cd backend
python -m venv venv
venv\Scripts\activate       # Windows
pip install -r requirements.txt
python manage.py migrate
python manage.py runserver
```

### Application Passager

```bash
cd mobile/mwamba_taxi
flutter pub get
flutter run
```

### Application Chauffeur

```bash
cd mobile/mwamba_driver
flutter pub get
flutter run
```

## API Documentation

- Swagger UI : `http://localhost:8000/api/docs/`
- ReDoc : `http://localhost:8000/api/redoc/`
- Admin Django : `http://localhost:8000/admin/`

## Fonctionnalités principales

### Passager
- Inscription / Connexion (téléphone + OTP)
- Recherche de destination avec lieux populaires de Kinshasa
- Estimation de prix en temps réel (CDF)
- Suivi du chauffeur en temps réel sur la carte
- Paiement Mobile Money
- Historique des courses
- Notation des chauffeurs
- Bouton SOS d'urgence
- Codes promotionnels

### Chauffeur
- Inscription avec informations véhicule
- Mode en ligne / hors ligne
- Réception de demandes de course en temps réel
- Navigation vers le passager et la destination
- Tableau de bord des revenus
- Historique des courses effectuées

### Administration
- Tableau de bord avec statistiques globales
- Gestion des chauffeurs (approbation, suspension)
- Suivi des courses et revenus
- Gestion des alertes SOS
- Graphiques de tendances

## Tarification Kinshasa

- Tarif de base : 1 500 CDF
- Prix par km : 800 CDF
- Prix par minute : 100 CDF
- Facteur route Kinshasa : ×1.3 (état des routes)
- Commission plateforme : 15%

## Licence

Propriétaire — Mwamba Taxi © 2024

### Mobile

```bash
cd mobile/mwamba_taxi
flutter pub get
flutter run
```

## API Documentation

Swagger UI: `http://localhost:8000/api/docs/`

## Licence

Propriétaire - Mwamba Taxi © 2026


Caleb@241986@
Haotshi@241986

# créer le dossier projet "propre"
mkdir -p /opt/Mwamba-taxi

# déplacer ton backend téléversé
mv /root/nginx /opt/Mwamba-taxi/

cd /opt
sudo git clone https://github.com/GMDesk/Mwamba-taxi.git
sudo chown -R $USER:$USER Mwamba-taxi
cd Mwamba-taxi

# Stopper nginx pour libérer port 80
docker compose -f docker-compose.prod.yml --env-file .env.production stop nginx

# Obtenir le certificat (remplacez votre@email.com)
sudo certbot certonly --standalone \
  -d mwambataxi.com \
  --email gedeonmandjuandja@gmail.com \
  --agree-tos \
  --non-interactive

# Vérifier
sudo ls /etc/letsencrypt/live/mwambataxi.com/