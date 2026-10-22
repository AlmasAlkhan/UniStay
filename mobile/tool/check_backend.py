"""Exercise the Flutter API client against Django using an ephemeral SQLite DB.

Run with backend/.venv Python. Does not touch backend/.env, db.sqlite3 or media.
This verifies sequential integration only, not PostgreSQL concurrency.
"""
import base64
import io
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
from wsgiref.simple_server import make_server, WSGIRequestHandler

mobile = Path(__file__).resolve().parents[1]
backend = mobile.parent / 'backend'
sys.path.insert(0, str(backend))

with tempfile.TemporaryDirectory(prefix='unistay-mobile-check-') as temp:
    os.environ.update(DJANGO_SETTINGS_MODULE='config.settings', DEBUG='true',
                      DATABASE_URL='sqlite:///' + (Path(temp) / 'test.sqlite3').as_posix(),
                      ALLOWED_HOSTS='127.0.0.1,localhost',
                      EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend')
    import django
    django.setup()
    from django.conf import settings
    from django.core.management import call_command
    from django.core.wsgi import get_wsgi_application
    from django.db import connections
    from core.models import User, Profile
    from PIL import Image
    settings.MEDIA_ROOT = str(Path(temp) / 'media')
    call_command('migrate', verbosity=0)
    for role, email, name in [('student', 'mobile-student@example.test', 'Mobile Student'),
                              ('landlord', 'mobile-owner@example.test', 'Mobile Owner')]:
        user = User.objects.create_user(email=email, password='Local-smoke-only-382!', name=name,
                                        role=role, email_verified=True)
        Profile.objects.create(user=user)
    photo = io.BytesIO()
    Image.new('RGB', (8, 8), '#2f6b55').save(photo, 'PNG')
    class QuietHandler(WSGIRequestHandler):
        def log_message(self, *args):
            pass
    server = make_server('127.0.0.1', 0, get_wsgi_application(), handler_class=QuietHandler)
    def serve():
        try:
            server.serve_forever()
        finally:
            connections.close_all()
    thread = threading.Thread(target=serve, daemon=True)
    thread.start()
    try:
        command = [shutil.which('flutter'), 'test', 'tool/live_api_test.dart',
                   f'--dart-define=LIVE_API_URL=http://127.0.0.1:{server.server_port}',
                   '--dart-define=LIVE_PHOTO=' + base64.b64encode(photo.getvalue()).decode()]
        result = subprocess.run(command, cwd=mobile)
    finally:
        server.shutdown()
        thread.join()
        server.server_close()
        connections.close_all()
    sys.exit(result.returncode)
