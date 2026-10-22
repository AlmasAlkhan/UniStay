#!/bin/bash
cd "$(dirname "$0")"
backend/scripts/local.sh start
printf '\nНажми Enter, чтобы закрыть окно.'
read -r
