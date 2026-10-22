from django.core.management.base import BaseCommand
from django.utils import timezone
from core.models import ApiSession
class Command(BaseCommand):
    help='Remove expired API sessions. Run periodically on the deployment host.'
    def handle(self,*args,**options):
        count,_=ApiSession.objects.filter(expires_at__lte=timezone.now()).delete()
        self.stdout.write(f'Removed {count} expired sessions.')
