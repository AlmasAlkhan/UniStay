import uuid
from django.contrib.auth.models import AbstractUser, BaseUserManager
from django.db import models
from django.db.models import Q
from django.db.models.functions import Lower
from django.core.validators import MinValueValidator, MaxValueValidator

class UserManager(BaseUserManager):
    def create_user(self, email, password=None, **extra):
        if not email:
            raise ValueError('Email is required')
        user = self.model(email=email.strip().lower(), **extra)
        user.set_password(password)
        user.save(using=self._db)
        return user
    def create_superuser(self, email, password=None, **extra):
        extra.setdefault('is_staff',True)
        extra.setdefault('is_superuser',True)
        extra.setdefault('email_verified',True)
        if not extra['is_staff'] or not extra['is_superuser']:
            raise ValueError('Superuser must be staff and superuser')
        return self.create_user(email,password,**extra)

class User(AbstractUser):
    class Role(models.TextChoices):
        STUDENT='student','Student'
        LANDLORD='landlord','Landlord'
    username = None
    email = models.EmailField(unique=True)
    name = models.CharField(max_length=120)
    role = models.CharField(max_length=10,choices=Role.choices,default=Role.STUDENT)
    email_verified = models.BooleanField(default=False)
    USERNAME_FIELD = 'email'
    REQUIRED_FIELDS = ['name']
    objects = UserManager()
    class Meta:
        constraints=[models.UniqueConstraint(Lower('email'),name='unique_email_case_insensitive')]

class Profile(models.Model):
    user=models.OneToOneField(User,on_delete=models.CASCADE,related_name='profile')
    university=models.CharField(max_length=160,blank=True)
    bio=models.CharField(max_length=1000,blank=True)
    schedule=models.CharField(max_length=10,choices=[('early','Early'),('late','Late')],blank=True)
    smoking=models.BooleanField(null=True,default=None)
    cleanliness=models.CharField(max_length=10,choices=[('tidy','Tidy'),('relaxed','Relaxed')],blank=True)
    share_with_group=models.BooleanField(default=False)

class ApiSession(models.Model):
    digest=models.CharField(max_length=64,unique=True)
    user=models.ForeignKey(User,on_delete=models.CASCADE,related_name='api_sessions')
    expires_at=models.DateTimeField()
    created_at=models.DateTimeField(auto_now_add=True)

class Listing(models.Model):
    class Status(models.TextChoices):
        DRAFT='draft','Draft'
        PUBLISHED='published','Published'
        ARCHIVED='archived','Archived'
    owner=models.ForeignKey(User,on_delete=models.PROTECT,related_name='listings')
    title=models.CharField(max_length=160)
    description=models.TextField(max_length=5000)
    city=models.CharField(max_length=100,default='Астана')
    district=models.CharField(max_length=100)
    address=models.CharField(max_length=255)
    university=models.CharField(max_length=160)
    price=models.DecimalField(max_digits=10,decimal_places=2,validators=[MinValueValidator(1)])
    deposit=models.DecimalField(max_digits=10,decimal_places=2,default=0,validators=[MinValueValidator(0)])
    utilities_included=models.BooleanField(default=False)
    capacity=models.PositiveSmallIntegerField(validators=[MinValueValidator(1),MaxValueValidator(6)])
    move_in_date=models.DateField(null=True,blank=True)
    status=models.CharField(max_length=12,choices=Status.choices,default=Status.DRAFT)
    created_at=models.DateTimeField(auto_now_add=True)
    updated_at=models.DateTimeField(auto_now=True)
    class Meta:
        ordering=['-created_at','-id']
        constraints=[models.CheckConstraint(condition=Q(capacity__gte=1,capacity__lte=6),name='valid_capacity'),
                     models.CheckConstraint(condition=Q(price__gt=0,deposit__gte=0),name='valid_prices')]
        indexes=[models.Index(fields=['status','city']),models.Index(fields=['price'])]


def photo_path(instance, filename):
    return f'listings/{instance.listing_id}/{uuid.uuid4().hex}.jpg'

class ListingPhoto(models.Model):
    listing=models.ForeignKey(Listing,on_delete=models.CASCADE,related_name='photos')
    image=models.ImageField(upload_to=photo_path)
    caption=models.CharField(max_length=160,blank=True)
    created_at=models.DateTimeField(auto_now_add=True)
    class Meta:
        ordering=['id']

class Application(models.Model):
    class Status(models.TextChoices):
        PENDING='pending','Pending'
        ACCEPTED='accepted','Accepted'
        REJECTED='rejected','Rejected'
        CANCELLED='cancelled','Cancelled'
    student=models.ForeignKey(User,on_delete=models.PROTECT,related_name='applications')
    listing=models.ForeignKey(Listing,on_delete=models.PROTECT,related_name='applications')
    status=models.CharField(max_length=12,choices=Status.choices,default=Status.PENDING)
    message=models.CharField(max_length=1000,blank=True)
    created_at=models.DateTimeField(auto_now_add=True)
    updated_at=models.DateTimeField(auto_now=True)
    class Meta:
        ordering=['-created_at','-id']
        constraints=[
            models.UniqueConstraint(fields=['student'],condition=Q(status='accepted'),name='one_accepted_place_per_student'),
            models.UniqueConstraint(fields=['student','listing'],condition=Q(status__in=['pending','accepted']),name='one_active_application_per_listing'),
        ]
        indexes=[models.Index(fields=['listing','status'])]

class ApplicationEvent(models.Model):
    application=models.ForeignKey(Application,on_delete=models.CASCADE,related_name='events')
    actor=models.ForeignKey(User,on_delete=models.PROTECT)
    from_status=models.CharField(max_length=12,blank=True)
    to_status=models.CharField(max_length=12)
    created_at=models.DateTimeField(auto_now_add=True)
    class Meta:
        ordering=['created_at','id']
