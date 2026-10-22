from rest_framework.exceptions import PermissionDenied

def verified(user):
    if not user.email_verified:
        raise PermissionDenied('Сначала подтвердите email.')

def role(user,required):
    if user.role!=required:
        raise PermissionDenied('Эта операция недоступна вашей роли.')
    verified(user)
