import io
from PIL import Image
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APIClient
from core.models import Listing,ListingPhoto,Application
import pytest

pytestmark=pytest.mark.django_db

def photo():
    f=io.BytesIO()
    Image.new('RGB',(32,32),'red').save(f,'PNG')
    return SimpleUploadedFile('unsafe-name.png',f.getvalue(),content_type='image/png')

def payload():
    return dict(title='New home',description='New description',city='Астана',district='Esil',address='Exact private address',university='AITU',price='90000.00',capacity=3)

def test_owner_create_photo_publish(owner,client_for):
    c=client_for(owner)
    r=c.post('/api/v1/listings/',payload())
    assert r.status_code==201
    pk=r.data['id']
    assert r.data['status']=='draft'
    assert c.patch(f'/api/v1/listings/{pk}/',{'status':'published'}).status_code==400
    r=c.post(f'/api/v1/listings/{pk}/photos/',{'image':photo(),'caption':'Living room'},format='multipart')
    assert r.status_code==201
    assert ListingPhoto.objects.get().image.name.endswith('.jpg')
    assert c.patch(f'/api/v1/listings/{pk}/',{'status':'published'}).status_code==200
    assert APIClient().get('/api/v1/listings/').data['count']==1

def test_public_draft_and_address_privacy(listing,make_listing,owner,student,client_for):
    draft=make_listing(status='draft')
    public=APIClient()
    r=public.get('/api/v1/listings/')
    assert r.data['count']==1 and r.data['results'][0]['address'] is None
    assert public.get(f'/api/v1/listings/{draft.pk}/').status_code==404
    assert client_for(owner).get(f'/api/v1/listings/{draft.pk}/').status_code==200
    Application.objects.create(student=student,listing=listing,status='accepted')
    assert client_for(student).get(f'/api/v1/listings/{listing.pk}/').data['address']=='Private address'

def test_foreign_owner_and_student_cannot_modify(listing,make_user,student,client_for):
    other=client_for(make_user('landlord'))
    assert other.patch(f'/api/v1/listings/{listing.pk}/',{'title':'Hacked'}).status_code==404
    assert other.delete(f'/api/v1/listings/{listing.pk}/').status_code==404
    assert client_for(student).post('/api/v1/listings/',payload()).status_code==403
    listing.refresh_from_db()
    assert listing.title=='Apartment'

def test_capacity_and_terms_cannot_invalidate_accepted(listing,owner,student,make_user,client_for):
    Application.objects.create(student=student,listing=listing,status='accepted')
    Application.objects.create(student=make_user(),listing=listing,status='accepted')
    c=client_for(owner)
    assert c.patch(f'/api/v1/listings/{listing.pk}/',{'capacity':1}).status_code==409
    assert c.patch(f'/api/v1/listings/{listing.pk}/',{'price':'99000.00'}).status_code==409
    assert c.patch(f'/api/v1/listings/{listing.pk}/',{'capacity':3}).status_code==200

def test_filters_validation_and_pagination(make_listing):
    make_listing(price=70000)
    make_listing(price=120000,district='Nura')
    c=APIClient()
    assert c.get('/api/v1/listings/?max_price=80000').data['count']==1
    assert c.get('/api/v1/listings/?district=Nura').data['count']==1
    assert c.get('/api/v1/listings/?ordering=price').data['results'][0]['price']=='70000.00'
    assert c.get('/api/v1/listings/?min_price=NaN').status_code==400
    assert c.get('/api/v1/listings/?available=maybe').status_code==400
    assert c.get('/api/v1/listings/?ordering=owner__email').status_code==400
    assert c.get('/api/v1/listings/?page=999').status_code==404

def test_photo_invalid_foreign_delete_and_limit(listing,owner,make_user,client_for,settings):
    c=client_for(owner)
    invalid=SimpleUploadedFile('x.jpg',b'<script>bad</script>',content_type='image/jpeg')
    assert c.post(f'/api/v1/listings/{listing.pk}/photos/',{'image':invalid},format='multipart').status_code==400
    settings.MAX_PHOTOS_PER_LISTING=1
    r=c.post(f'/api/v1/listings/{listing.pk}/photos/',{'image':photo()},format='multipart')
    assert r.status_code==201
    assert c.post(f'/api/v1/listings/{listing.pk}/photos/',{'image':photo()},format='multipart').status_code==409
    pid=r.data['id']
    assert client_for(make_user('landlord')).delete(f'/api/v1/photos/{pid}/').status_code==404
    assert c.delete(f'/api/v1/photos/{pid}/').status_code==409
    assert c.patch(f'/api/v1/listings/{listing.pk}/',{'status':'draft'}).status_code==200
    assert c.delete(f'/api/v1/photos/{pid}/').status_code==204
    assert not ListingPhoto.objects.exists()

def test_archive_preserves_history_and_accepted_access(listing,owner,student,client_for):
    app=Application.objects.create(student=student,listing=listing,status='accepted')
    assert client_for(owner).delete(f'/api/v1/listings/{listing.pk}/').status_code==204
    assert APIClient().get(f'/api/v1/listings/{listing.pk}/').status_code==404
    assert client_for(student).get(f'/api/v1/listings/{listing.pk}/').status_code==200
    assert Application.objects.filter(pk=app.pk).exists()

def test_group_consent_no_email_and_explainable_score(listing,student,make_user,client_for):
    resident=make_user()
    Application.objects.create(student=resident,listing=listing,status='accepted')
    c=client_for(student)
    assert c.get(f'/api/v1/listings/{listing.pk}/group/').data==[]
    resident.profile.share_with_group=True
    resident.profile.save()
    r=c.get(f'/api/v1/listings/{listing.pk}/group/')
    assert len(r.data)==1 and r.data[0]['compatibility']==100
    assert r.data[0]['compared_preferences']==3
    assert 'email' not in r.data[0]
    assert APIClient().get(f'/api/v1/listings/{listing.pk}/group/').status_code==401

def test_photo_size_limit(listing,owner,client_for,settings):
    settings.MAX_PHOTO_BYTES=1
    r=client_for(owner).post(f'/api/v1/listings/{listing.pk}/photos/',{'image':photo()},format='multipart')
    assert r.status_code==400 and not ListingPhoto.objects.exists()

def test_invalid_pk_returns_404(owner,client_for):
    c=client_for(owner)
    assert c.patch('/api/v1/listings/abc/',{'title':'X'}).status_code==404
    assert c.post('/api/v1/applications/abc/accept/').status_code==404

def test_null_address_and_capacity_validation(owner,client_for):
    c=client_for(owner)
    data=payload()
    data['address']=None
    assert c.post('/api/v1/listings/',data).status_code==400
    data=payload()
    data['capacity']=0
    assert c.post('/api/v1/listings/',data).status_code==400
