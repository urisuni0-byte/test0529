FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

COPY --from=ghcr.io/astral-sh/uv:0.9.26 /uv /uvx /bin/

WORKDIR /app

COPY uv.lock pyproject.toml ./
RUN uv sync --frozen --no-dev --no-install-project

COPY ./app ./app
COPY ./alembic.ini .
COPY ./prestart.sh .

ENV PATH="/app/.venv/bin:$PATH"

EXPOSE 8000

CMD ["sh", "prestart.sh"]
