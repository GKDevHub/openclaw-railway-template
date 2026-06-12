# OpenClaw Railway Template
#
# Two-layer install: the image ships a seed version via npm (fast, reliable
# build), and the entrypoint bootstraps it onto the Railway persistent volume
# so that `openclaw update` writes there and survives container restarts.
FROM node:22-bookworm
ENV NODE_ENV=production

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    tini \
    python3 \
    python3-venv \
  && rm -rf /var/lib/apt/lists/*

# `openclaw update` and plugin installs expect pnpm.
RUN corepack enable && corepack prepare pnpm@10.23.0 --activate

# Seed OpenClaw version in the image (fallback + first-boot source).
# Override OPENCLAW_VERSION in Railway template settings to pin a different release.
ARG OPENCLAW_VERSION=2026.6.6
RUN npm install -g --no-audit --no-fund "openclaw@${OPENCLAW_VERSION}" \
  && npm cache clean --force

WORKDIR /app

# Wrapper deps
COPY package.json ./
RUN npm install --omit=dev && npm cache clean --force

COPY src ./src
COPY --chmod=755 entrypoint.sh ./entrypoint.sh

# Persist user-installed tools by default by targeting the Railway volume.
# - npm global installs -> /data/npm
# - pnpm global installs -> /data/pnpm (binaries) + /data/pnpm-store (store)
ENV NPM_CONFIG_PREFIX=/data/npm
ENV NPM_CONFIG_CACHE=/data/npm-cache
ENV PNPM_HOME=/data/pnpm
ENV PNPM_STORE_DIR=/data/pnpm-store
ENV PATH="/data/npm/bin:/data/pnpm:${PATH}"

# The wrapper listens on $PORT.
# IMPORTANT: Do not set a default PORT here.
# Railway injects PORT at runtime and routes traffic to that port.
EXPOSE 8080

# tini ensures PID 1 reaps zombies and forwards signals.
# entrypoint.sh bootstraps the volume install, then execs the wrapper.
ENTRYPOINT ["tini", "--", "./entrypoint.sh"]
