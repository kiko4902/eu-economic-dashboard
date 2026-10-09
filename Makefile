# Load DB settings from .env (if present) and export them to recipes.
-include .env
export

# Dependencies are pinned in uv.lock (cross-platform); uv installs Python 3.12 if needed.
UV ?= uv

ifeq ($(OS),Windows_NT)
    VENV_BIN := .venv/Scripts
else
    VENV_BIN := .venv/bin
endif

VENV_PY := $(VENV_BIN)/python

.PHONY: help up down install lock db-shell pipeline extract warehouse transform reconcile analytics quality test lint

help:
	@echo "Targets: up down install lock db-shell pipeline extract warehouse transform reconcile analytics quality test lint"

up:  ## Start PostgreSQL and wait until it is healthy
	docker compose up -d --wait

down:  ## Stop PostgreSQL (data volume is kept)
	docker compose down

install:  ## Create .venv with exactly the versions in uv.lock (fails if the lock is outdated)
	$(UV) sync --locked --extra dev

lock:  ## Upgrade all dependencies to their latest allowed versions and rewrite uv.lock
	$(UV) lock --upgrade
	$(UV) sync --locked --extra dev

db-shell:  ## Open psql inside the DB container
	docker compose exec db psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)

pipeline:  ## Full ETL: extract -> warehouse -> transform -> analytics -> quality checks
	$(VENV_PY) -m pipeline.run

extract:  ## Download Eurostat datasets into the raw schema
	$(VENV_PY) -m pipeline.extract

warehouse:  ## Create warehouse tables and populate dimensions
	$(VENV_PY) -m pipeline.warehouse

transform:  ## Load the fact table from raw, then reconcile raw vs fact row counts
	$(VENV_PY) -m pipeline.transform
	$(VENV_PY) -m pipeline.quality reconciliation

analytics:  ## Create the analytics views and the read-only Power BI role
	$(VENV_PY) -m pipeline.analytics

reconcile:  ## Reconcile raw vs fact row counts (every difference must have a skip reason)
	$(VENV_PY) -m pipeline.quality reconciliation

quality:  ## All data quality checks; results in quality.check_run / quality.check_result
	$(VENV_PY) -m pipeline.quality

test:
	$(VENV_PY) -m pytest

lint:
	$(VENV_BIN)/ruff check src tests
	$(VENV_BIN)/ruff format --check src tests
