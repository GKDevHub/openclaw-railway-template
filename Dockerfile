# Install OpenClaw from the published npm package.
#
# Older revisions of this template built OpenClaw from source because some dist
# files were not shipped on npm. That is no longer true: the published package
# ships a complete, self-contained `dist/`. Installing from npm makes the build
# fast and reliable and avoids the out-of-memory failures that the source build
# hit on smaller Railway tiers.
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

# `openclaw update` and plugin installs expect pnpm. Provide it in the runtime image.
RUN corepack enable && corepack prepare pnpm@10.23.0 --activate

# Install OpenClaw from npm at a pinned version.
# Override in Railway template settings to use a different release (e.g. "latest").
ARG OPENCLAW_VERSION=2026.6.1
RUN npm install --omit=dev --no-audit --no-fund --prefix /openclaw "openclaw@${OPENCLAW_VERSION}" \
  && npm cache clean --force

# The wrapper runs the CLI entry directly to avoid PATH/global-install mismatches.
ENV OPENCLAW_ENTRY=/openclaw/node_modules/openclaw/dist/entry.js

# Provide an `openclaw` executable on PATH (used by the smoke test + setup Debug Console).
RUN printf '%s\n' '#!/usr/bin/env bash' 'exec node /openclaw/node_modules/openclaw/dist/entry.js "$@"' > /usr/local/bin/openclaw \
  && chmod +x /usr/local/bin/openclaw

WORKDIR /app

# Wrapper deps
COPY package.json ./
RUN npm install --omit=dev && npm cache clean --force

COPY src ./src

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
# If we force a different port, deployments can come up but the domain will route elsewhere.
EXPOSE 8080

# Ensure PID 1 reaps zombies and forwards signals.
ENTRYPOINT ["tini", "--"]
CMD ["node", "src/server.js"]
