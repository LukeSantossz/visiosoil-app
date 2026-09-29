.PHONY: setup folds train evaluate contrasts deploy test pipeline all clean

PYTHON = .venv/bin/python
PIP = .venv/bin/pip
PYTEST = .venv/bin/pytest
VERSION ?= v1
ARM ?= cnn

setup:
	python -m venv .venv
	$(PIP) install --upgrade pip
	$(PIP) install -r requirements.txt

folds:
	$(PYTHON) scripts/validate_dataset.py --version $(VERSION) --splits-dir data/splits

train:
	$(PYTHON) -m src.crossval --version $(VERSION) --arm $(ARM)

evaluate:
	$(PYTHON) -m src.evaluate --version $(VERSION) --arm $(ARM)

contrasts:
	$(PYTHON) -m src.evaluate --version $(VERSION) --contrasts

deploy:
	bash scripts/deploy_to_app.sh $(VERSION)

test:
	$(PYTEST) tests/ -v

pipeline: folds train evaluate

all: pipeline

clean:
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name .pytest_cache -exec rm -rf {} + 2>/dev/null || true
	rm -rf data/processed/*
