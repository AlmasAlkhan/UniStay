import pytest
from rest_framework.test import APIClient
from core.models import Application,ApplicationEvent

pytestmark=pytest.mark.django_db

def test_complete_lifecycle_and_idempotency(listing,student,owner,client_for):
    sc,oc=client_for(student),client_for(owner)
    r=sc.post('/api/v1/applications/',{'listing_id':listing.pk,'message':'Hello'})
    assert r.status_code==201
    pk=r.data['id']
    assert APIClient().get(f'/api/v1/listings/{listing.pk}/').data['available']==2
    assert oc.post(f'/api/v1/applications/{pk}/accept/').status_code==200
    assert oc.post(f'/api/v1/applications/{pk}/accept/').status_code==200
    assert ApplicationEvent.objects.count()==2
    assert APIClient().get(f'/api/v1/listings/{listing.pk}/').data['available']==1
    assert sc.post(f'/api/v1/applications/{pk}/cancel/').status_code==200
    assert sc.post(f'/api/v1/applications/{pk}/cancel/').status_code==200
    assert ApplicationEvent.objects.count()==3
    assert APIClient().get(f'/api/v1/listings/{listing.pk}/').data['available']==2
    assert sc.post('/api/v1/applications/',{'listing_id':listing.pk}).status_code==201

def test_duplicate_incomplete_and_unverified(listing,student,client_for,make_user):
    c=client_for(student)
    assert c.post('/api/v1/applications/',{'listing_id':listing.pk}).status_code==201
    assert c.post('/api/v1/applications/',{'listing_id':listing.pk}).status_code==409
    unverified=client_for(make_user(verified=False))
    assert unverified.post('/api/v1/applications/',{'listing_id':listing.pk}).status_code==403
    u=make_user()
    u.profile.university=''
    u.profile.save()
    assert client_for(u).post('/api/v1/applications/',{'listing_id':listing.pk}).status_code==400

def test_access_separation(listing,student,owner,make_user,client_for):
    app=Application.objects.create(student=student,listing=listing)
    stranger=client_for(make_user())
    assert stranger.get('/api/v1/applications/').data['count']==0
    assert stranger.get(f'/api/v1/applications/{app.pk}/').status_code==404
    assert stranger.post(f'/api/v1/applications/{app.pk}/cancel/').status_code==404
    assert client_for(student).post(f'/api/v1/applications/{app.pk}/accept/').status_code==404
    assert client_for(owner).post(f'/api/v1/applications/{app.pk}/cancel/').status_code==404
    assert client_for(owner).get('/api/v1/applications/').data['count']==1

def test_one_accepted_place_and_last_slot(make_listing,student,make_user,owner,client_for):
    a,b=make_listing(capacity=1),make_listing(capacity=1)
    other=make_user()
    x=Application.objects.create(student=student,listing=a)
    y=Application.objects.create(student=student,listing=b)
    z=Application.objects.create(student=other,listing=a)
    c=client_for(owner)
    assert c.post(f'/api/v1/applications/{x.pk}/accept/').status_code==200
    assert c.post(f'/api/v1/applications/{y.pk}/accept/').status_code==409
    assert c.post(f'/api/v1/applications/{z.pk}/accept/').status_code==409
    assert APIClient().get(f'/api/v1/listings/{a.pk}/').data['group_ready']

def test_rejection_terminal_and_archive(make_listing,listing,student,owner,client_for):
    app=Application.objects.create(student=student,listing=listing)
    c=client_for(owner)
    assert c.post(f'/api/v1/applications/{app.pk}/reject/').status_code==200
    assert c.post(f'/api/v1/applications/{app.pk}/accept/').status_code==409
    other=make_listing(status='archived')
    x=Application.objects.create(student=student,listing=other)
    assert c.post(f'/api/v1/applications/{x.pk}/accept/').status_code==409

def test_pending_limit(make_listing,student,client_for):
    for _ in range(5): Application.objects.create(student=student,listing=make_listing())
    assert client_for(student).post('/api/v1/applications/',{'listing_id':make_listing().pk}).status_code==409
