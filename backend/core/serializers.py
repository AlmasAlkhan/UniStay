from django.contrib.auth import get_user_model
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import transaction
from rest_framework import serializers
from drf_spectacular.utils import extend_schema_field
from .models import User, Profile, Listing, ListingPhoto, Application, ApplicationEvent

class RegisterSerializer(serializers.Serializer):
    email=serializers.EmailField()
    password=serializers.CharField(write_only=True,min_length=10,max_length=128)
    name=serializers.CharField(max_length=120)
    role=serializers.ChoiceField(choices=User.Role.choices)
    def validate(self,data):
        data['email']=data['email'].strip().lower()
        if User.objects.filter(email__iexact=data['email']).exists():
            raise serializers.ValidationError({'email':'Этот email уже зарегистрирован.'})
        try:
            validate_password(data['password'],User(email=data['email'],name=data['name']))
        except DjangoValidationError as e:
            raise serializers.ValidationError({'password':list(e.messages)})
        return data
    @transaction.atomic
    def create(self,data):
        user=User.objects.create_user(**data)
        Profile.objects.create(user=user)
        return user

class LoginSerializer(serializers.Serializer):
    email=serializers.EmailField()
    password=serializers.CharField(write_only=True,max_length=128)

class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model=User
        fields=['id','email','name','role','email_verified']
        read_only_fields=fields

class ProfileSerializer(serializers.ModelSerializer):
    class Meta:
        model=Profile
        fields=['university','bio','schedule','smoking','cleanliness','share_with_group']

class MeSerializer(UserSerializer):
    profile=ProfileSerializer(read_only=True)
    class Meta(UserSerializer.Meta):
        fields=UserSerializer.Meta.fields+['profile']

class TokenResponseSerializer(serializers.Serializer):
    token=serializers.CharField()
    expires_at=serializers.DateTimeField()
    user=MeSerializer()

class MessageSerializer(serializers.Serializer):
    detail=serializers.CharField()

class EmailSerializer(serializers.Serializer):
    email=serializers.EmailField()

class VerifySerializer(serializers.Serializer):
    token=serializers.CharField(max_length=2048)

class ResetConfirmSerializer(serializers.Serializer):
    uid=serializers.CharField(max_length=128)
    token=serializers.CharField(max_length=256)
    password=serializers.CharField(write_only=True,min_length=10,max_length=128)

class PhotoSerializer(serializers.ModelSerializer):
    class Meta:
        model=ListingPhoto
        fields=['id','image','caption']
        read_only_fields=['id','image']

class PhotoUploadSerializer(serializers.Serializer):
    image=serializers.ImageField()
    caption=serializers.CharField(max_length=160,required=False,allow_blank=True)

class ListingSerializer(serializers.ModelSerializer):
    address=serializers.CharField(max_length=255,allow_null=True,help_text='Exact address; null in responses for guests and non-accepted students. Required non-null on creation.')
    photos=PhotoSerializer(many=True,read_only=True)
    owner=serializers.IntegerField(source='owner_id',read_only=True)
    owner_name=serializers.CharField(source='owner.name',read_only=True)
    occupied=serializers.SerializerMethodField()
    available=serializers.SerializerMethodField()
    group_ready=serializers.SerializerMethodField()
    class Meta:
        model=Listing
        fields=['id','owner','owner_name','title','description','city','district','address','university',
                'price','deposit','utilities_included','capacity','move_in_date','status','photos',
                'occupied','available','group_ready','created_at','updated_at']
        read_only_fields=['id','created_at','updated_at']
    def validate_address(self,value):
        if not value:
            raise serializers.ValidationError('Укажите адрес.')
        return value
    def validate(self,data):
        if data.get('status')=='published' and (not self.instance or not self.instance.photos.exists()):
            raise serializers.ValidationError({'status':'Перед публикацией добавьте хотя бы одну фотографию.'})
        return data
    @extend_schema_field(int)
    def get_occupied(self,obj):
        return getattr(obj,'taken',None) if hasattr(obj,'taken') else obj.applications.filter(status='accepted').count()
    @extend_schema_field(int)
    def get_available(self,obj):
        return obj.capacity-self.get_occupied(obj)
    @extend_schema_field(bool)
    def get_group_ready(self,obj):
        return self.get_available(obj)==0
    def to_representation(self,instance):
        result=super().to_representation(instance)
        user=self.context['request'].user
        if not user.is_authenticated or (user.pk!=instance.owner_id and not instance.applications.filter(student=user,status='accepted').exists()):
            result['address']=None
        return result

class ApplicationCreateSerializer(serializers.Serializer):
    listing_id=serializers.IntegerField(min_value=1)
    message=serializers.CharField(max_length=1000,allow_blank=True,required=False,default='')

class EventSerializer(serializers.ModelSerializer):
    class Meta:
        model=ApplicationEvent
        fields=['from_status','to_status','created_at','actor_id']

class ApplicantSerializer(serializers.ModelSerializer):
    profile=ProfileSerializer(read_only=True)
    class Meta:
        model=User
        fields=['id','name','profile']

class ApplicationSerializer(serializers.ModelSerializer):
    student=ApplicantSerializer(read_only=True)
    listing_id=serializers.IntegerField(read_only=True)
    listing_title=serializers.CharField(source='listing.title',read_only=True)
    events=EventSerializer(many=True,read_only=True)
    class Meta:
        model=Application
        fields=['id','listing_id','listing_title','student','status','message','created_at','updated_at','events']
        read_only_fields=fields

class GroupMemberSerializer(serializers.Serializer):
    id=serializers.IntegerField()
    name=serializers.CharField()
    university=serializers.CharField()
    bio=serializers.CharField()
    schedule=serializers.CharField()
    smoking=serializers.BooleanField(allow_null=True)
    cleanliness=serializers.CharField()
    compatibility=serializers.IntegerField(allow_null=True)
    matching_preferences=serializers.ListField(child=serializers.CharField())
    compared_preferences=serializers.IntegerField()
