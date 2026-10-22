import pytest
from django.core.management import call_command
from rest_framework.test import APIClient

@pytest.mark.django_db
def test_schema_and_health():
    c=APIClient()
    assert c.get('/health/').json()=={'status':'ok'}
    r=c.get('/api/schema/?format=json')
    assert r.status_code==200
    assert '/api/v1/applications/{id}/accept/' in r.data['paths']
    assert 'bearerAuth' in r.data['components']['securitySchemes']
