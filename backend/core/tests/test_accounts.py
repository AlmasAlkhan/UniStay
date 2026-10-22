from urllib.parse import urlsplit,parse_qs
from django.core import mail
from django.utils import timezone
from datetime import timedelta
from rest_framework.test import APIClient
from core.models import User,ApiSession
from core.auth import issue_session
import pytest

pytestmark=pytest.mark.django_db

def test_register_verify_login_logout():
    c=APIClient()
    r=c.post('/api/v1/auth/register/',{'email':'Test@Example.com','password':'Secure-Testing-Pass-908!','name':'Tester','role':'student'})
    assert r.status_code==201
    u=User.objects.get()
    assert u.email=='test@example.com' and not u.email_verified
    assert u.check_password('Secure-Testing-Pass-908!')
    assert 'password' not in r.data
    token=parse_qs(urlsplit(mail.outbox[0].body.splitlines()[0]).query)['token'][0]
    assert c.post('/api/v1/auth/verify-email/',{'token':token}).status_code==200
    r=c.post('/api/v1/auth/login/',{'email':u.email,'password':'Secure-Testing-Pass-908!'})
    assert r.status_code==200 and r.data['user']['email_verified']
    assert not ApiSession.objects.filter(digest=r.data['token']).exists()
    c.credentials(HTTP_AUTHORIZATION='Bearer '+r.data['token'])
    assert c.get('/api/v1/me/').status_code==200
    assert c.post('/api/v1/auth/logout/').status_code==204
    assert c.get('/api/v1/me/').status_code==401

def test_register_cannot_promote_privileges():
    c=APIClient()
    r=c.post('/api/v1/auth/register/',{'email':'a@example.com','password':'Secure-Testing-Pass-908!','name':'A','role':'student','is_staff':True,'email_verified':True})
    assert r.status_code==201
    u=User.objects.get()
    assert not u.is_staff and not u.email_verified

def test_weak_password_and_invalid_role():
    c=APIClient()
    assert c.post('/api/v1/auth/register/',{'email':'a@example.com','password':'123','name':'A','role':'admin'}).status_code==400
    assert not User.objects.exists()

def test_duplicate_email_case_insensitive(student):
    c=APIClient()
    assert c.post('/api/v1/auth/register/',{'email':student.email.upper(),'password':'Secure-Testing-Pass-908!','name':'A','role':'student'}).status_code==400

def test_unverified_write_denied(make_user,client_for):
    c=client_for(make_user('landlord',verified=False))
    assert c.post('/api/v1/listings/',{'title':'x'}).status_code in (400,403)
    # Permission must hold even with a structurally valid listing.
    assert c.post('/api/v1/listings/',{'title':'x','description':'x','district':'x','address':'x','university':'x','price':100,'capacity':2}).status_code==403

def test_invalid_and_expired_bearer(student):
    c=APIClient()
    c.credentials(HTTP_AUTHORIZATION='Bearer unknown')
    assert c.get('/api/v1/me/').status_code==401
    raw,_=issue_session(student)
    ApiSession.objects.update(expires_at=timezone.now()-timedelta(seconds=1))
    c.credentials(HTTP_AUTHORIZATION='Bearer '+raw)
    assert c.get('/api/v1/me/').status_code==401

def test_reset_invalidates_sessions_and_cannot_replay(student,client_for):
    old=client_for(student)
    c=APIClient()
    assert c.post('/api/v1/auth/password-reset/',{'email':student.email}).status_code==200
    params=parse_qs(urlsplit(mail.outbox[0].body.splitlines()[0]).query)
    payload={'uid':params['uid'][0],'token':params['token'][0],'password':'Another-Secure-Pass-928!'}
    assert c.post('/api/v1/auth/password-reset/confirm/',payload).status_code==200
    assert old.get('/api/v1/me/').status_code==401
    assert c.post('/api/v1/auth/password-reset/confirm/',payload).status_code==400
    assert c.post('/api/v1/auth/login/',{'email':student.email,'password':payload['password']}).status_code==200

def test_reset_unknown_account_generic(student):
    c=APIClient()
    existing=c.post('/api/v1/auth/password-reset/',{'email':student.email})
    absent=c.post('/api/v1/auth/password-reset/',{'email':'absent@example.com'})
    assert existing.data==absent.data

def test_invalid_verification_and_reset():
    c=APIClient()
    assert c.post('/api/v1/auth/verify-email/',{'token':'invalid'}).status_code==400
    assert c.post('/api/v1/auth/password-reset/confirm/',{'uid':'invalid','token':'invalid','password':'Another-Secure-Pass-928!'}).status_code==400

def test_login_throttling():
    c=APIClient()
    codes=[c.post('/api/v1/auth/login/',{'email':'absent@example.com','password':'wrong'}).status_code for _ in range(11)]
    assert codes[-1]==429

def test_profile_validation_and_no_role_change(student,client_for):
    c=client_for(student)
    r=c.patch('/api/v1/me/profile/',{'university':'NU','share_with_group':True,'role':'landlord'})
    assert r.status_code==200
    student.refresh_from_db()
    assert student.role=='student'
    assert c.patch('/api/v1/me/profile/',{'schedule':'invalid'}).status_code==400
