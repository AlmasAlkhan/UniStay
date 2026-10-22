from concurrent.futures import ThreadPoolExecutor
import threading
from django.db import connection,close_old_connections,connections
from rest_framework.test import APIClient
from core.models import Application
from core.auth import issue_session
import pytest

pytestmark=pytest.mark.django_db(transaction=True)

def race(owner,ids):
    token,_=issue_session(owner)
    barrier=threading.Barrier(2)
    def accept(pk):
        close_old_connections()
        try:
            c=APIClient()
            c.credentials(HTTP_AUTHORIZATION='Bearer '+token)
            barrier.wait(timeout=10)
            return c.post(f'/api/v1/applications/{pk}/accept/').status_code
        finally: connections.close_all()
    with ThreadPoolExecutor(2) as pool:
        return sorted(pool.map(accept,ids))

def test_postgres_last_place(make_listing,make_user,owner):
    if connection.vendor!='postgresql': pytest.skip('Row-lock concurrency requires PostgreSQL')
    listing=make_listing(capacity=1)
    apps=[Application.objects.create(student=make_user(),listing=listing) for _ in range(2)]
    assert race(owner,[a.pk for a in apps])==[200,409]
    assert Application.objects.filter(status='accepted').count()==1

def test_postgres_same_student_two_flats(make_listing,make_user,owner):
    if connection.vendor!='postgresql': pytest.skip('Row-lock concurrency requires PostgreSQL')
    student=make_user()
    apps=[Application.objects.create(student=student,listing=make_listing()) for _ in range(2)]
    assert race(owner,[a.pk for a in apps])==[200,409]
    assert Application.objects.filter(status='accepted').count()==1
