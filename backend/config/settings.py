import os
from pathlib import Path
from django.core.exceptions import ImproperlyConfigured
import dj_database_url
from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / '.env')
DEBUG = os.getenv('DEBUG', 'true').lower() == 'true'
SECRET_KEY = os.getenv('SECRET_KEY', 'local-development-only-not-for-production')
if not DEBUG and (SECRET_KEY.startswith('local-') or len(SECRET_KEY) < 50):
    raise ImproperlyConfigured('Set a random SECRET_KEY of at least 50 characters.')
ALLOWED_HOSTS = os.getenv('ALLOWED_HOSTS', 'localhost,127.0.0.1,testserver').split(',')
INSTALLED_APPS = [
    'django.contrib.admin','django.contrib.auth','django.contrib.contenttypes',
    'django.contrib.sessions','django.contrib.messages','django.contrib.staticfiles',
    'rest_framework','drf_spectacular','corsheaders','core.apps.CoreConfig',
]
MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware','corsheaders.middleware.CorsMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware','django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware','django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware','django.middleware.clickjacking.XFrameOptionsMiddleware',
]
ROOT_URLCONF = 'config.urls'
WSGI_APPLICATION = 'config.wsgi.application'
TEMPLATES = [{'BACKEND':'django.template.backends.django.DjangoTemplates','DIRS':[],'APP_DIRS':True,
    'OPTIONS':{'context_processors':['django.template.context_processors.request',
    'django.contrib.auth.context_processors.auth','django.contrib.messages.context_processors.messages']}}]
DATABASES = {'default': dj_database_url.config(default=f'sqlite:///{BASE_DIR / "db.sqlite3"}', conn_max_age=60)}
if not DEBUG and DATABASES['default']['ENGINE'].endswith('sqlite3'):
    raise ImproperlyConfigured('Production requires PostgreSQL DATABASE_URL.')
AUTH_USER_MODEL = 'core.User'
AUTH_PASSWORD_VALIDATORS = [
    {'NAME':'django.contrib.auth.password_validation.UserAttributeSimilarityValidator'},
    {'NAME':'django.contrib.auth.password_validation.MinimumLengthValidator','OPTIONS':{'min_length':10}},
    {'NAME':'django.contrib.auth.password_validation.CommonPasswordValidator'},
    {'NAME':'django.contrib.auth.password_validation.NumericPasswordValidator'},
]
LANGUAGE_CODE = 'ru'
TIME_ZONE = 'Asia/Almaty'
USE_I18N = True
USE_TZ = True
STATIC_URL = '/static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'
MEDIA_ROOT = BASE_DIR / 'media'
MEDIA_URL = '/media/'
DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'
CORS_ALLOWED_ORIGINS = os.getenv('CORS_ALLOWED_ORIGINS','http://localhost:3000,http://127.0.0.1:3000').split(',')
CSRF_TRUSTED_ORIGINS = os.getenv('CSRF_TRUSTED_ORIGINS','').split(',') if os.getenv('CSRF_TRUSTED_ORIGINS') else []
SESSION_COOKIE_SECURE = not DEBUG
CSRF_COOKIE_SECURE = not DEBUG
SECURE_SSL_REDIRECT = not DEBUG
SECURE_HSTS_SECONDS = 31536000 if not DEBUG else 0
SECURE_HSTS_INCLUDE_SUBDOMAINS = not DEBUG
SECURE_HSTS_PRELOAD = not DEBUG
SECURE_CONTENT_TYPE_NOSNIFF = True
# Enable only behind a trusted reverse proxy that strips incoming forwarded headers.
if os.getenv('TRUST_PROXY_HTTPS') == 'true':
    SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')
EMAIL_BACKEND = os.getenv('EMAIL_BACKEND','django.core.mail.backends.console.EmailBackend')
EMAIL_HOST = os.getenv('EMAIL_HOST','')
EMAIL_PORT = int(os.getenv('EMAIL_PORT','587'))
EMAIL_HOST_USER = os.getenv('EMAIL_HOST_USER','')
EMAIL_HOST_PASSWORD = os.getenv('EMAIL_HOST_PASSWORD','')
EMAIL_USE_TLS = os.getenv('EMAIL_USE_TLS','true') == 'true'
DEFAULT_FROM_EMAIL = os.getenv('DEFAULT_FROM_EMAIL','UniStay <noreply@localhost>')
FRONTEND_URL = os.getenv('FRONTEND_URL','http://localhost:3000').rstrip('/')
if not DEBUG and (EMAIL_BACKEND.endswith('console.EmailBackend') or not FRONTEND_URL.startswith('https://')):
    raise ImproperlyConfigured('Production requires real email backend and HTTPS FRONTEND_URL.')
PASSWORD_RESET_TIMEOUT = 3600
TOKEN_HOURS = 24
MAX_PHOTO_BYTES = 5 * 1024 * 1024
MAX_PHOTOS_PER_LISTING = 10
DATA_UPLOAD_MAX_MEMORY_SIZE = 7 * 1024 * 1024
FILE_UPLOAD_MAX_MEMORY_SIZE = 5 * 1024 * 1024
REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES':['core.auth.BearerAuthentication'],
    'DEFAULT_PERMISSION_CLASSES':['rest_framework.permissions.IsAuthenticated'],
    'DEFAULT_PAGINATION_CLASS':'rest_framework.pagination.PageNumberPagination','PAGE_SIZE':20,
    'DEFAULT_SCHEMA_CLASS':'drf_spectacular.openapi.AutoSchema',
    'DEFAULT_THROTTLE_CLASSES':['rest_framework.throttling.AnonRateThrottle','rest_framework.throttling.UserRateThrottle'],
    'DEFAULT_THROTTLE_RATES':{'anon':'120/min','user':'300/min','auth':'10/min','email':'5/hour'},
    'EXCEPTION_HANDLER':'core.errors.exception_handler',
    'DEFAULT_RENDERER_CLASSES':['rest_framework.renderers.JSONRenderer'],
    'TEST_REQUEST_DEFAULT_FORMAT':'json',
}
SPECTACULAR_SETTINGS = {
    'TITLE':'UniStay API','DESCRIPTION':'Shared API for web and Flutter clients.',
    'VERSION':'1.0.0','SERVE_INCLUDE_SCHEMA':False,'COMPONENT_SPLIT_REQUEST':True,
    'ENUM_NAME_OVERRIDES':{'UserRoleEnum':['student','landlord'],
        'ApplicationStatusEnum':['pending','accepted','rejected','cancelled'],'ListingStatusEnum':['draft','published','archived']},
}

CACHES = {'default': {'BACKEND': 'django.core.cache.backends.locmem.LocMemCache' if DEBUG else 'django.core.cache.backends.db.DatabaseCache', 'LOCATION': 'unistay_cache'}}
