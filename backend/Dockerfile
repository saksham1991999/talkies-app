FROM python:3.12-slim

# uv installs the locked dependencies. The image holds no build tools after that.
COPY --from=ghcr.io/astral-sh/uv:0.11 /uv /usr/local/bin/uv

ENV PYTHONUNBUFFERED=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PROJECT_ENVIRONMENT=/opt/venv \
    PATH="/opt/venv/bin:$PATH" \
    PORT=8000

WORKDIR /app
COPY pyproject.toml uv.lock ./
# The cache goes in the same layer as the sync, so the image does not carry a
# second copy of every wheel. (The uv binary itself stays; removing it needs a
# multi-stage build.)
RUN uv sync --frozen --no-dev --no-install-project && rm -rf /root/.cache/uv

COPY app ./app

RUN useradd --system --no-create-home talkies
USER talkies

EXPOSE 8000

# --proxy-headers makes the rate limiter see the real client IP behind a proxy.
# Run the container only behind a proxy that sets X-Forwarded-For itself.
CMD exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --proxy-headers --forwarded-allow-ips='*'
