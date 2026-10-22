import pytest
from django.core.cache import cache
from rest_framework.test import APIClient
from core.models import User,Profile,Listing
from core.auth import issue_session

@pytest.fixture(autouse=True)
def isolated(settings,tmp_path):
    settings.EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend'
    settings.MEDIA_ROOT=tmp_path/'media'
    cache.clear()

@pytest.fixture
def make_user(db):
    def make(role='student',email=None,verified=True):
        email=email or f'{role}-{User.objects.count()}@example.com'
        user=User.objects.create_user(email=email,password='Secure-Testing-Pass-908!',name=email.split('@')[0],role=role,email_verified=verified)
        Profile.objects.create(user=user,university='AITU',schedule='early',smoking=False,cleanliness='tidy')
        return user
    return make

@pytest.fixture
def owner(make_user): return make_user('landlord')

@pytest.fixture
def student(make_user): return make_user()

@pytest.fixture
def make_listing(owner):
    def make(**extra):
        data=dict(owner=owner,title='Apartment',description='Description',district='Esil',address='Private address',university='AITU',price='85000.00',capacity=2,status='published')
        data.update(extra)
        return Listing.objects.create(**data)
    return make

@pytest.fixture
def listing(make_listing): return make_listing()

@pytest.fixture
def client_for():
    def make(user):
        client=APIClient()
        token,_=issue_session(user)
        client.credentials(HTTP_AUTHORIZATION=f'Bearer {token}')
        return client
    return make
