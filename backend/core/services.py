from django.db import transaction
from rest_framework.exceptions import NotFound, PermissionDenied, ValidationError
from .errors import Conflict
from .models import User, Listing, Application, ApplicationEvent
from .permissions import role


def event(application,actor,old=''):
    ApplicationEvent.objects.create(application=application,actor=actor,from_status=old,to_status=application.status)

@transaction.atomic
def apply(student,listing_id,message):
    role(student,'student')
    # Fixed order: student then listing. All changes affecting occupancy use this order.
    User.objects.select_for_update().get(pk=student.pk)
    listing=Listing.objects.select_for_update().filter(pk=listing_id,status='published').first()
    if not listing:
        raise NotFound('Объявление не найдено или снято с публикации.')
    profile=student.profile
    if not all([profile.university,profile.schedule,profile.cleanliness]) or profile.smoking is None:
        raise ValidationError('Перед заявкой заполните университет и бытовые привычки.')
    if Application.objects.filter(student=student,status='accepted').exists():
        raise Conflict('У вас уже есть принятое место.')
    if Application.objects.filter(student=student,listing=listing,status__in=['pending','accepted']).exists():
        raise Conflict('Заявка на эту квартиру уже существует.')
    if Application.objects.filter(student=student,status='pending').count()>=5:
        raise Conflict('Можно иметь не больше пяти ожидающих заявок.')
    if listing.applications.filter(status='accepted').count()>=listing.capacity:
        raise Conflict('Свободных мест нет.')
    application=Application.objects.create(student=student,listing=listing,message=message)
    event(application,student)
    return application

@transaction.atomic
def transition(actor,application_id,target):
    info=Application.objects.filter(pk=application_id).values('student_id','listing_id').first()
    if not info:
        raise NotFound()
    User.objects.select_for_update().get(pk=info['student_id'])
    listing=Listing.objects.select_for_update().get(pk=info['listing_id'])
    application=Application.objects.select_for_update().get(pk=application_id)
    if target=='cancelled':
        if application.student_id!=actor.id:
            raise NotFound()
    else:
        if listing.owner_id!=actor.id:
            raise NotFound()
        role(actor,'landlord')
    if application.status==target:
        return application  # Retrying a successful request is idempotent.
    if target=='cancelled':
        if application.status not in ('pending','accepted'):
            raise Conflict('Эту заявку уже нельзя отменить.')
    elif application.status!='pending':
        raise Conflict('Решение допустимо только для ожидающей заявки.')
    if target=='accepted':
        if listing.status!='published':
            raise Conflict('Нельзя принять заявку на неопубликованную квартиру.')
        if not application.student.is_active or not application.student.email_verified:
            raise Conflict('Аккаунт студента недоступен или email не подтверждён.')
        if Application.objects.filter(student_id=info['student_id'],status='accepted').exists():
            raise Conflict('У студента уже есть другое принятое место.')
        if listing.applications.filter(status='accepted').count()>=listing.capacity:
            raise Conflict('Последнее место уже занято.')
    old=application.status
    application.status=target
    application.save(update_fields=['status','updated_at'])
    event(application,actor,old)
    return application
