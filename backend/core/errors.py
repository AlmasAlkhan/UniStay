from rest_framework.views import exception_handler as drf_handler
from rest_framework.exceptions import APIException
class Conflict(APIException):
    status_code=409
    default_detail='Операция конфликтует с текущим состоянием.'
    default_code='conflict'

def exception_handler(exc,context):
    response=drf_handler(exc,context)
    if response is not None:
        response.data={'error':{'status':response.status_code,'details':response.data}}
    return response
