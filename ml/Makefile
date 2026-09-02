.PHONY: setup folds train evaluate contrasts export deploy test pipeline all clean

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

# Not part of `pipeline`: cross-validation produces one model per fold per
# repeat under models/$(VERSION)/$(ARM)/repeat-<r>/fold-<i>/, and src.export
# reads models/$(VERSION)/model.keras. Which fold's model ships is a release
# decision the evaluation protocol does not make, so promoting one is a
# deliberate step and not something `make pipeline` should do on the way past.
export:
	$(PYTHON) -m src.export --version $(VERSION)

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
