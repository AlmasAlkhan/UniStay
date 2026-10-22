import hashlib
import secrets
from datetime import timedelta
from django.conf import settings
from django.utils import timezone
from rest_framework.authentication import BaseAuthentication, get_authorization_header
from rest_framework.exceptions import AuthenticationFailed
from .models import ApiSession


def issue_session(user):
    token=secrets.token_urlsafe(40)
    expires=timezone.now()+timedelta(hours=settings.TOKEN_HOURS)
    ApiSession.objects.create(user=user,digest=hashlib.sha256(token.encode()).hexdigest(),expires_at=expires)
    return token,expires

class BearerAuthentication(BaseAuthentication):
    def authenticate(self,request):
        parts=get_authorization_header(request).split()
        if not parts:
            return None
        if len(parts)!=2 or parts[0].lower()!=b'bearer':
            raise AuthenticationFailed('Используйте Authorization: Bearer <token>.')
        digest=hashlib.sha256(parts[1]).hexdigest()
        session=ApiSession.objects.select_related('user').filter(digest=digest,expires_at__gt=timezone.now(),user__is_active=True).first()
        if not session:
            raise AuthenticationFailed('Сессия истекла или недействительна.')
        return session.user,session
    def authenticate_header(self,request):
        return 'Bearer'
