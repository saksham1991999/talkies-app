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

# --proxy-headers makes uvicorn believe X-Forwarded-For, but only from the
# addresses in TRUSTED_PROXIES: the same list the rate limiter reads, and the
# same rule (trust nobody but loopback unless the deployment says otherwise).
# Never '*': a directly reachable container would then let any client pick its
# own IP and its own rate-limit bucket.
ENV TRUSTED_PROXIES=127.0.0.1,::1
CMD exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --proxy-headers --forwarded-allow-ips="${TRUSTED_PROXIES}"
