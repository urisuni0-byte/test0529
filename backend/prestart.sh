#!/bin/sh
set -e

echo "Waiting for database..."
python app/backend_pre_start.py

echo "Running Alembic migrations..."
alembic upgrade head

echo "Creating initial data..."
python app/initial_data.py

echo "Starting FastAPI server..."
exec fastapi run --workers 1 app/main.py --port 8000
