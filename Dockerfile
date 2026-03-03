# syntax=docker/dockerfile:1-labs

# Build argument for custom certificates directory
ARG CUSTOM_CERT_DIR="certs"

FROM node:20-alpine3.22 AS node_base

FROM node:20-alpine3.22 AS node_deps
WORKDIR /app
# Install git to clone the repository
RUN apk add --no-cache git && \
    git clone https://github.com/AsyncFuncAI/deepwiki-open.git .

RUN npm ci --legacy-peer-deps

FROM node:20-alpine3.22 AS node_builder
WORKDIR /app
# Copy the cloned repository and dependencies
COPY --from=node_deps /app ./

# Increase Node.js memory limit for build and disable telemetry
ENV NODE_OPTIONS="--max-old-space-size=4096"
ENV NEXT_TELEMETRY_DISABLED=1
RUN NODE_ENV=production npm run build

FROM python:3.11-slim AS py_deps
WORKDIR /api
# Install git to clone the repository
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates && rm -rf /var/lib/apt/lists/*
RUN git clone https://github.com/AsyncFuncAI/deepwiki-open.git /repo && \
    cp /repo/api/pyproject.toml . && \
    cp /repo/api/poetry.lock .

RUN python -m pip install poetry==2.0.1 --no-cache-dir && \
    poetry config virtualenvs.create true --local && \
    poetry config virtualenvs.in-project true --local && \
    poetry config virtualenvs.options.always-copy --local true && \
    POETRY_MAX_WORKERS=10 poetry install --no-interaction --no-ansi --only main && \
    poetry cache clear --all .

# ────────────────────────────────────────────────
# 使用 Python 脚本自动下载 tiktoken 缓存
# ────────────────────────────────────────────────
RUN mkdir -p /tiktoken_cache && chmod 755 /tiktoken_cache

# 先确认 tiktoken 和 requests 已安装
RUN /api/.venv/bin/pip list 2>/dev/null | grep -i tiktoken && \
    /api/.venv/bin/pip list 2>/dev/null | grep -i requests && \
    echo "=== tiktoken and requests are installed ==="

# 写入下载脚本并执行
RUN echo 'import os; os.environ["TIKTOKEN_CACHE_DIR"] = "/tiktoken_cache"' > /tmp/dl_tiktoken.py && \
    echo 'import tiktoken' >> /tmp/dl_tiktoken.py && \
    echo 'e1 = tiktoken.get_encoding("cl100k_base")' >> /tmp/dl_tiktoken.py && \
    echo 'e2 = tiktoken.get_encoding("o200k_base")' >> /tmp/dl_tiktoken.py && \
    echo 'print("cl100k_base vocab size:", e1.n_vocab)' >> /tmp/dl_tiktoken.py && \
    echo 'print("o200k_base vocab size:", e2.n_vocab)' >> /tmp/dl_tiktoken.py && \
    echo 'import glob; files = glob.glob("/tiktoken_cache/*"); print("Cached files:", files)' >> /tmp/dl_tiktoken.py && \
    echo 'assert len(files) >= 2, f"Expected >=2 cache files, got {len(files)}"' >> /tmp/dl_tiktoken.py && \
    echo 'print("=== Tiktoken cache downloaded and verified ===")'  >> /tmp/dl_tiktoken.py && \
    /api/.venv/bin/python /tmp/dl_tiktoken.py

# 二次确认缓存文件存在
RUN echo "=== Tiktoken cache files ===" && ls -la /tiktoken_cache/



# ────────────────────────────────────────────────
# Final image
# ────────────────────────────────────────────────
FROM python:3.11-slim AS final

# Set working directory
WORKDIR /app

# Install Node.js and npm
RUN apt-get update && apt-get install -y \
    curl \
    gnupg \
    git \
    ca-certificates \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install -y nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Update certificates if custom ones were provided and copied successfully
RUN if [ -n "${CUSTOM_CERT_DIR}" ]; then \
    mkdir -p /usr/local/share/ca-certificates && \
    if [ -d "${CUSTOM_CERT_DIR}" ]; then \
    cp -r ${CUSTOM_CERT_DIR}/* /usr/local/share/ca-certificates/ 2>/dev/null || true; \
    update-ca-certificates; \
    echo "Custom certificates installed successfully."; \
    else \
    echo "Warning: ${CUSTOM_CERT_DIR} not found. Skipping certificate installation."; \
    fi \
    fi

ENV PATH="/opt/venv/bin:$PATH"

# Copy Python dependencies and tiktoken cache
COPY --from=py_deps /api/.venv /opt/venv
COPY --from=py_deps /repo/api ./api/
COPY --from=py_deps /tiktoken_cache /tiktoken_cache

# ────────────────────────────────────────────────
# 离线验证：确认 tiktoken 能从本地缓存加载，不联网
# 如果验证失败，构建会报错退出
# ────────────────────────────────────────────────
RUN echo "=== Verifying tiktoken offline cache in final image ===" && \
    ls -la /tiktoken_cache/ && \
    TIKTOKEN_CACHE_DIR=/tiktoken_cache python -c "\
    import tiktoken; \
    enc1 = tiktoken.get_encoding('cl100k_base'); \
    enc2 = tiktoken.get_encoding('o200k_base'); \
    print('=== Offline tiktoken verification PASSED ==='); \
    print('cl100k_base vocab size:', enc1.n_vocab); \
    print('o200k_base vocab size:', enc2.n_vocab)"

# Copy Node app
COPY --from=node_builder /app/public ./public
COPY --from=node_builder /app/.next/standalone ./
COPY --from=node_builder /app/.next/static ./.next/static

# Expose the port the app runs on
EXPOSE ${PORT:-8001} 3000

# Create a script to run both backend and frontend
RUN echo '#!/bin/bash\n\
    # Ensure tiktoken cache dir is set (must be before .env loading)\n\
    export TIKTOKEN_CACHE_DIR=/tiktoken_cache\n\
    export DATA_GYM_CACHE_DIR=/tiktoken_cache\n\
    \n\
    # Load environment variables from .env file if it exists\n\
    if [ -f .env ]; then\n\
    # Save tiktoken cache dir before .env loading\n\
    _SAVED_TIKTOKEN_CACHE_DIR="$TIKTOKEN_CACHE_DIR"\n\
    export $(grep -v "^#" .env | xargs -r)\n\
    # Restore tiktoken cache dir (prevent .env from overriding it)\n\
    export TIKTOKEN_CACHE_DIR="$_SAVED_TIKTOKEN_CACHE_DIR"\n\
    export DATA_GYM_CACHE_DIR="$_SAVED_TIKTOKEN_CACHE_DIR"\n\
    fi\n\
    \n\
    # Check for required environment variables\n\
    if [ -z "$OPENAI_API_KEY" ] || [ -z "$GOOGLE_API_KEY" ]; then\n\
    echo "Warning: OPENAI_API_KEY and/or GOOGLE_API_KEY environment variables are not set."\n\
    echo "These are required for DeepWiki to function properly."\n\
    echo "You can provide them via a mounted .env file or as environment variables when running the container."\n\
    fi\n\
    \n\
    # Start the API server in the background with the configured port\n\
    python -m api.main --port ${PORT:-8001} &\n\
    PORT=3000 HOSTNAME=0.0.0.0 node server.js &\n\
    wait -n\n\
    exit $?' > /app/start.sh && chmod +x /app/start.sh

# Set environment variables
ENV PORT=8001
ENV NODE_ENV=production
ENV SERVER_BASE_URL=http://localhost:${PORT:-8001}
ENV TIKTOKEN_CACHE_DIR=/tiktoken_cache
ENV DATA_GYM_CACHE_DIR=/tiktoken_cache

# Create empty .env file (will be overridden if one exists at runtime)
RUN touch .env

# Command to run the application
CMD ["/app/start.sh"]