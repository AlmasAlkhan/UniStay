PYTHON := .venv/bin/python
.PHONY: setup migrate test check schema run
setup:
	python3 -m venv .venv
	$(PYTHON) -m pip install -r requirements.txt
migrate:
	$(PYTHON) manage.py migrate
check:
	$(PYTHON) manage.py check
	$(PYTHON) manage.py makemigrations --check --dry-run
schema:
	$(PYTHON) manage.py spectacular --file ../docs/openapi.yaml --validate --fail-on-warn
test:
	$(PYTHON) -m pytest
run:
	$(PYTHON) manage.py runserver 127.0.0.1:8000
