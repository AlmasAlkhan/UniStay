#!/bin/bash
set -euo pipefail
if [[ "${1:-}" == verify && "${2:-}" != /* ]]; then
  set -- verify "$PWD/${2:?Specify backup file}"
fi
cd "$(dirname "$0")/.."
export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"
compose=(docker compose --env-file .env.local -f compose.local.yaml)
case "${1:-start}" in
 start) "${compose[@]}" up -d --wait ;;
 stop) "${compose[@]}" stop ;;
 status) "${compose[@]}" ps ;;
 logs) "${compose[@]}" logs --tail=80 api ;;
 backup|verify) exec .venv/bin/python scripts/backup.py "$@" ;;
 *) echo 'Usage: local.sh start|stop|status|logs|backup|verify BACKUP'; exit 2 ;;
esac
