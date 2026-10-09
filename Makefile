# Load DB settings from .env (if present) and export them to recipes.
-include .env
export

# Project targets Python 3.12 (override: make install PYTHON=/path/to/python3.12)
PYTHON ?= python3.12

ifeq ($(OS),Windows_NT)
    VENV_BIN := .venv/Scripts
else
    VENV_BIN := .venv/bin
endif

VENV_PY := $(VENV_BIN)/python

.PHONY: help up down install db-shell pipeline extract transform test lint

help:
	@echo "Targets: up down install db-shell pipeline extract transform test lint"

up:  ## Start PostgreSQL and wait until it is healthy
	docker compose up -d --wait

down:  ## Stop PostgreSQL (data volume is kept)
	docker compose down

install:  ## Create .venv and install the package with dev dependencies
	$(PYTHON) -m venv .venv
	$(VENV_PY) -m pip install --upgrade pip
	$(VENV_PY) -m pip install -e ".[dev]"

db-shell:  ## Open psql inside the DB container
	docker compose exec db psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)

pipeline:  ## Full ETL: extract + transform
	$(VENV_PY) -m pipeline.run

extract:
	@echo "extract: not implemented yet (Phase 1)"

transform:
	@echo "transform: not implemented yet (Phase 3)"

test:
	@echo "test: not implemented yet (Phase 5)"

lint:
	$(VENV_BIN)/ruff check src tests
	$(VENV_BIN)/ruff format --check src tests
