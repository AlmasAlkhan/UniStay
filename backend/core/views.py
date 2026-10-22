import io
import warnings
from decimal import Decimal, InvalidOperation
from urllib.parse import urlencode
from PIL import Image, ImageOps, UnidentifiedImageError
from django.conf import settings
from django.contrib.auth import authenticate
from django.contrib.auth.password_validation import validate_password
from django.contrib.auth.tokens import default_token_generator
from django.core import signing
from django.core.exceptions import ValidationError as DjangoValidationError
from django.core.files.base import ContentFile
from django.core.mail import send_mail
from django.db import transaction, IntegrityError, connection
from django.db.models import Q, Count, F
from django.http import JsonResponse
from django.utils.encoding import force_bytes, force_str
from django.utils.http import urlsafe_base64_encode, urlsafe_base64_decode
from rest_framework import viewsets, generics, status
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.decorators import action
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.exceptions import AuthenticationFailed, ValidationError, NotFound, PermissionDenied, APIException
from rest_framework.parsers import MultiPartParser, FormParser
from rest_framework.throttling import ScopedRateThrottle
from drf_spectacular.utils import extend_schema, extend_schema_view, OpenApiParameter
from .models import User, Profile, Listing, ListingPhoto, Application
from .serializers import *
from .auth import issue_session
from .permissions import role, verified
from .errors import Conflict
from .services import apply, transition


def send_account_mail(user,kind):
    if kind=='verify':
        params={'token':signing.dumps({'id':user.pk,'email':user.email},salt='verify-email')}
        path='verify-email'
        subject='UniStay: подтвердите email'
    else:
        params={'uid':urlsafe_base64_encode(force_bytes(user.pk)),'token':default_token_generator.make_token(user)}
        path='reset-password'
        subject='UniStay: восстановление пароля'
    link=f'{settings.FRONTEND_URL}/{path}?{urlencode(params)}'
    send_mail(subject,f'{link}\nЕсли вы не запрашивали это действие, проигнорируйте письмо.',settings.DEFAULT_FROM_EMAIL,[user.email],fail_silently=False)

class AuthView(APIView):
    permission_classes=[AllowAny]
    authentication_classes=[]
    throttle_classes=[ScopedRateThrottle]
    throttle_scope='auth'

class RegisterView(AuthView):
    @extend_schema(request=RegisterSerializer,responses={201:MeSerializer})
    def post(self,request):
        serializer=RegisterSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            user=serializer.save()
        except IntegrityError:
            raise Conflict('Этот email уже зарегистрирован.')
        try:
            send_account_mail(user,'verify')
        except Exception:
            # Account survives delivery failure; resend endpoint can recover it.
            raise APIException('Аккаунт создан, но письмо не доставлено. Запросите подтверждение повторно.')
        return Response(MeSerializer(user).data,status=201)

class LoginView(AuthView):
    @extend_schema(request=LoginSerializer,responses=TokenResponseSerializer)
    def post(self,request):
        serializer=LoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user=authenticate(request,email=serializer.validated_data['email'].lower(),password=serializer.validated_data['password'])
        if not user:
            raise AuthenticationFailed('Неверный email или пароль.')
        token,expires=issue_session(user)
        return Response({'token':token,'expires_at':expires,'user':MeSerializer(user).data})

class LogoutView(APIView):
    @extend_schema(request=None,responses={204:None})
    def post(self,request):
        request.auth.delete()
        return Response(status=204)

class MeView(generics.RetrieveAPIView):
    serializer_class=MeSerializer
    def get_object(self):
        return self.request.user

class ProfileView(generics.RetrieveUpdateAPIView):
    serializer_class=ProfileSerializer
    http_method_names=['get','patch','head','options']
    def get_object(self):
        return Profile.objects.get_or_create(user=self.request.user)[0]

class EmailRequestView(AuthView):
    throttle_scope='email'
    kind='verify'
    @extend_schema(request=EmailSerializer,responses=MessageSerializer)
    def post(self,request):
        s=EmailSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        user=User.objects.filter(email__iexact=s.validated_data['email'],is_active=True).first()
        if user and (self.kind=='reset' or not user.email_verified):
            try:
                send_account_mail(user,self.kind)
            except Exception:
                # Preserve identical response for existing and absent accounts.
                import logging
                logging.getLogger(__name__).error('Account email delivery failed; check provider configuration.')
        return Response({'detail':'Если аккаунт существует и действие требуется, письмо будет отправлено.'})

class ResetRequestView(EmailRequestView):
    kind='reset'

class VerifyView(AuthView):
    @extend_schema(request=VerifySerializer,responses=MessageSerializer)
    def post(self,request):
        s=VerifySerializer(data=request.data)
        s.is_valid(raise_exception=True)
        try:
            payload=signing.loads(s.validated_data['token'],salt='verify-email',max_age=86400)
            user=User.objects.get(pk=payload['id'],email=payload['email'],is_active=True)
        except (signing.BadSignature,User.DoesNotExist,KeyError,TypeError,ValueError):
            raise ValidationError('Ссылка недействительна или истекла.')
        user.email_verified=True
        user.save(update_fields=['email_verified'])
        return Response({'detail':'Email подтверждён.'})

class ResetConfirmView(AuthView):
    @extend_schema(request=ResetConfirmSerializer,responses=MessageSerializer)
    def post(self,request):
        s=ResetConfirmSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        data=s.validated_data
        with transaction.atomic():
            try:
                user=User.objects.select_for_update().get(pk=force_str(urlsafe_base64_decode(data['uid'])),is_active=True)
            except (ValueError,TypeError,OverflowError,User.DoesNotExist,UnicodeDecodeError):
                raise ValidationError('Ссылка недействительна или истекла.')
            if not default_token_generator.check_token(user,data['token']):
                raise ValidationError('Ссылка недействительна или истекла.')
            try:
                validate_password(data['password'],user)
            except DjangoValidationError as e:
                raise ValidationError({'password':e.messages})
            user.set_password(data['password'])
            user.save(update_fields=['password'])
            user.api_sessions.all().delete()
        return Response({'detail':'Пароль изменён. Войдите заново.'})

LIST_FILTERS=[OpenApiParameter(name,typ,OpenApiParameter.QUERY) for name,typ in [
    ('search',str),('city',str),('district',str),('university',str),('min_price',float),('max_price',float),
    ('available',bool),('ordering',str)]]

@extend_schema_view(list=extend_schema(parameters=LIST_FILTERS))
class ListingViewSet(viewsets.ModelViewSet):
    lookup_value_regex=r'\d+'
    serializer_class=ListingSerializer
    http_method_names=['get','post','patch','delete','head','options']
    def get_permissions(self):
        return [AllowAny()] if self.action in ('list','retrieve') else [IsAuthenticated()]
    def get_queryset(self):
        qs=Listing.objects.select_related('owner').prefetch_related('photos').annotate(taken=Count('applications',filter=Q(applications__status='accepted')))
        if getattr(self,'swagger_fake_view',False):
            return qs.none()
        user=self.request.user
        if self.action=='mine':
            return qs.filter(owner=user)
        if self.action in ('list','retrieve','group'):
            if user.is_authenticated:
                qs=qs.filter(Q(status='published')|Q(owner=user)|Q(pk__in=Application.objects.filter(student=user,status='accepted').values('listing_id')))
            else:
                qs=qs.filter(status='published')
        else:
            qs=qs.filter(owner=user)
        if self.action=='list':
            # Owner's drafts are reachable by detail/mine but not the public catalogue.
            qs=qs.filter(status='published')
            p=self.request.query_params
            for field in ('city','district','university'):
                if p.get(field): qs=qs.filter(**{f'{field}__icontains':p[field]})
            if p.get('search'): qs=qs.filter(Q(title__icontains=p['search'])|Q(description__icontains=p['search']))
            for param,op in (('min_price','gte'),('max_price','lte')):
                if param in p:
                    try:
                        value=Decimal(p[param])
                        if not value.is_finite() or value<0 or value>99999999: raise ValueError()
                    except (InvalidOperation,ValueError):
                        raise ValidationError({param:'Ожидается неотрицательное число до 99999999.'})
                    qs=qs.filter(**{f'price__{op}':value})
            if p.get('available'):
                if p['available'] not in ('true','false'):
                    raise ValidationError({'available':'Используйте true или false.'})
                qs=qs.filter(taken__lt=F('capacity')) if p['available']=='true' else qs.filter(taken__gte=F('capacity'))
            ordering=p.get('ordering','-created_at')
            if ordering not in ('price','-price','created_at','-created_at'):
                raise ValidationError({'ordering':'Допустимо: price, -price, created_at, -created_at.'})
            qs=qs.order_by(ordering,'id')
        return qs
    def perform_create(self,serializer):
        role(self.request.user,'landlord')
        serializer.save(owner=self.request.user)
    def update(self,request,*args,**kwargs):
        role(request.user,'landlord')
        with transaction.atomic():
            # Same listing lock used by application acceptance and photo mutations.
            obj=Listing.objects.select_for_update().filter(pk=kwargs['pk'],owner=request.user).first()
            if not obj: raise NotFound()
            s=self.get_serializer(obj,data=request.data,partial=True)
            s.is_valid(raise_exception=True)
            occupied=obj.applications.filter(status='accepted').count()
            if s.validated_data.get('capacity',obj.capacity)<occupied:
                raise Conflict('Нельзя уменьшить вместимость ниже числа принятых жильцов.')
            if occupied and any(k in s.validated_data and s.validated_data[k]!=getattr(obj,k) for k in ('price','deposit','utilities_included','move_in_date')):
                raise Conflict('При принятых жильцах условия аренды нельзя менять без отдельного согласования.')
            s.save()
            return Response(s.data)
    def destroy(self,request,*args,**kwargs):
        role(request.user,'landlord')
        with transaction.atomic():
            obj=Listing.objects.select_for_update().filter(pk=kwargs['pk'],owner=request.user).first()
            if not obj: raise NotFound()
            # Soft deletion retains application history and tenant access.
            obj.status='archived'
            obj.save(update_fields=['status','updated_at'])
        return Response(status=204)
    @action(detail=False,methods=['get'])
    def mine(self,request):
        role(request.user,'landlord')
        page=self.paginate_queryset(self.get_queryset())
        return self.get_paginated_response(self.get_serializer(page,many=True).data)
    @extend_schema(request=PhotoUploadSerializer,responses={201:PhotoSerializer})
    @action(detail=True,methods=['post'],parser_classes=[MultiPartParser,FormParser])
    def photos(self,request,pk=None):
        role(request.user,'landlord')
        obj=self.get_object()
        s=PhotoUploadSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        uploaded=s.validated_data['image']
        if uploaded.size>settings.MAX_PHOTO_BYTES:
            raise ValidationError({'image':'Максимальный размер — 5 MiB.'})
        try:
            with warnings.catch_warnings():
                warnings.simplefilter('error',Image.DecompressionBombWarning)
                uploaded.seek(0)
                img=Image.open(uploaded)
                if img.format not in ('JPEG','PNG','WEBP') or img.width*img.height>20_000_000:
                    raise ValueError()
                img.load()
                img=ImageOps.exif_transpose(img).convert('RGB')
                img.thumbnail((2400,2400))
                result=io.BytesIO()
                # Re-encode rather than trusting filenames, MIME, or EXIF metadata.
                img.save(result,format='JPEG',quality=85)
        except (UnidentifiedImageError,ValueError,OSError,Image.DecompressionBombError,Image.DecompressionBombWarning):
            raise ValidationError({'image':'Нужен JPEG, PNG или WebP до 20 мегапикселей.'})
        photo=None
        try:
            with transaction.atomic():
                Listing.objects.select_for_update().get(pk=obj.pk)
                if obj.photos.count()>=settings.MAX_PHOTOS_PER_LISTING:
                    raise Conflict('Можно загрузить не больше 10 фотографий.')
                photo=ListingPhoto(listing=obj,caption=s.validated_data.get('caption',''))
                photo.image.save('photo.jpg',ContentFile(result.getvalue()),save=False)
                photo.save()
        except Exception:
            if photo and photo.image: photo.image.delete(save=False)
            raise
        return Response(PhotoSerializer(photo,context={'request':request}).data,status=201)
    @extend_schema(responses=GroupMemberSerializer(many=True))
    @action(detail=True,methods=['get'])
    def group(self,request,pk=None):
        verified(request.user)
        listing=self.get_object()
        me=Profile.objects.get_or_create(user=request.user)[0]
        items=[]
        for app in listing.applications.filter(status='accepted').select_related('student__profile'):
            profile=app.student.profile
            if not profile.share_with_group and listing.owner_id!=request.user.id and app.student_id!=request.user.id:
                continue
            data={'id':app.student_id,'name':app.student.name,**ProfileSerializer(profile).data}
            keys=[k for k in ('schedule','smoking','cleanliness') if getattr(profile,k) not in ('',None) and getattr(me,k) not in ('',None)]
            matches=[k for k in keys if getattr(profile,k)==getattr(me,k)]
            data.update(compatibility=round(len(matches)/len(keys)*100) if keys and request.user.role=='student' and app.student_id!=request.user.id else None,
                        matching_preferences=matches,compared_preferences=len(keys))
            data.pop('share_with_group',None)
            items.append(data)
        return Response(items)

class PhotoDeleteView(APIView):
    @extend_schema(responses={204:None})
    def delete(self,request,pk):
        role(request.user,'landlord')
        photo=ListingPhoto.objects.filter(pk=pk,listing__owner=request.user).first()
        if not photo: raise NotFound()
        with transaction.atomic():
            listing=Listing.objects.select_for_update().get(pk=photo.listing_id)
            if listing.status=='published' and listing.photos.count()<=1:
                raise Conflict('Нельзя удалить последнее фото опубликованного объявления. Сначала снимите его с публикации.')
            photo.delete()
            transaction.on_commit(lambda:photo.image.delete(save=False))
        return Response(status=204)

class ApplicationViewSet(viewsets.ReadOnlyModelViewSet):
    lookup_value_regex=r'\d+'
    serializer_class=ApplicationSerializer
    def get_queryset(self):
        if getattr(self,'swagger_fake_view',False):
            return Application.objects.none()
        return Application.objects.filter(Q(student=self.request.user)|Q(listing__owner=self.request.user)).select_related('student__profile','listing').prefetch_related('events')
    @extend_schema(request=ApplicationCreateSerializer,responses={201:ApplicationSerializer})
    def create(self,request):
        s=ApplicationCreateSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        app=apply(request.user,**s.validated_data)
        return Response(self.get_serializer(app).data,status=201)
    @extend_schema(request=None,responses=ApplicationSerializer)
    @action(detail=True,methods=['post'])
    def accept(self,request,pk=None):
        return Response(self.get_serializer(transition(request.user,pk,'accepted')).data)
    @extend_schema(request=None,responses=ApplicationSerializer)
    @action(detail=True,methods=['post'])
    def reject(self,request,pk=None):
        return Response(self.get_serializer(transition(request.user,pk,'rejected')).data)
    @extend_schema(request=None,responses=ApplicationSerializer)
    @action(detail=True,methods=['post'])
    def cancel(self,request,pk=None):
        return Response(self.get_serializer(transition(request.user,pk,'cancelled')).data)


def health(request):
    try:
        with connection.cursor() as cursor:
            cursor.execute('SELECT 1')
        return JsonResponse({'status':'ok'})
    except Exception:
        return JsonResponse({'status':'unavailable'},status=503)
