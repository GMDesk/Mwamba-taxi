import time
from django.core.management.base import BaseCommand
from django.db import connections
from django.db.utils import OperationalError


class Command(BaseCommand):
    help = 'Attend que la base de données soit disponible'

    def handle(self, *args, **options):
        self.stdout.write('Attente de la base de données...')
        max_retries = 30
        for i in range(max_retries):
            try:
                connections['default'].ensure_connection()
                self.stdout.write(self.style.SUCCESS('Base de données disponible!'))
                return
            except OperationalError:
                self.stdout.write(f'Tentative {i+1}/{max_retries}...')
                time.sleep(2)
        self.stdout.write(self.style.ERROR('Base de données non disponible après 60s'))
        raise SystemExit(1)
