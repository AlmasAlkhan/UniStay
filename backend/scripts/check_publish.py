"""Read-only local publication check. Never contacts a remote or prints secrets."""
import pathlib
import re
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parents[2]
def git(*args):
    return subprocess.check_output(['git', '-C', str(root), *args])

staged = '--staged' in sys.argv
if staged:
    names = git('diff', '--cached', '--name-only', '--diff-filter=ACMR', '-z')
else:
    names = git('ls-files', '--cached', '--others', '--exclude-standard', '-z')
files = sorted(set(n.decode() for n in names.split(b'\0') if n))
secrets = []
for env in (root / 'backend/.env.local', root / 'backend/.env'):
    if env.exists():
        for line in env.read_text().splitlines():
            if '=' in line and not line.lstrip().startswith('#'):
                key, value = line.split('=', 1)
                value = value.strip().strip('\"\'')
                if any(word in key.upper() for word in ('PASSWORD', 'SECRET', 'TOKEN', 'DATABASE_URL')) and len(value) >= 12:
                    secrets.append(value.encode())
key = root / 'backend/.local/backup.key'
if key.exists():
    secrets.append(key.read_bytes().strip())
blocked = []
for name in files:
    path = pathlib.PurePosixPath(name)
    sensitive = any(p in {'.local', '.recovery', '.venv', 'venv', 'media', 'uploads', 'backups', '__pycache__'} for p in path.parts)
    sensitive |= path.name.startswith('.env') and path.name != '.env.example'
    sensitive |= bool(re.search(r'\.(sqlite3?|db)(-|$)|\.(sql|dump|backup|enc|hmac|key|pem|p12|pfx|log)$', name))
    data = git('show', ':' + name) if staged else (root / name).read_bytes()
    sensitive |= any(secret in data for secret in secrets if secret)
    sensitive |= bool(re.search(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}', data))
    if sensitive:
        blocked.append(name)
if blocked:
    print('STOP: review these paths; sensitive values are not displayed:')
    print('\n'.join(blocked))
    sys.exit(1)
print(f'OK: {len(files)} files checked. No local secrets or forbidden data files detected.')
print('This check covers known secrets and common patterns, not every possible credential.')
