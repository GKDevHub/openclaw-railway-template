---
name: testing-railway-template
description: Test the OpenClaw Railway template end-to-end using Docker. Covers build, onboarding, upgrade path, and gateway health verification.
---

# Testing the OpenClaw Railway Template

## Overview

The template uses a **two-layer npm install**: the Docker image seeds an OpenClaw version, and `entrypoint.sh` bootstraps it to a persistent volume (`/data/openclaw`). Testing verifies builds, onboarding, version upgrades, and gateway health.

## Prerequisites

- Docker available on the test machine
- npm registry accessible
- No external API keys needed for basic testing (dummy keys work for onboarding)

## Key Environment Variables

When running the container, set these for proper volume persistence:

```bash
-e PORT=8080
-e SETUP_PASSWORD=test123
-e OPENCLAW_STATE_DIR=/data/.openclaw
-e OPENCLAW_WORKSPACE_DIR=/data/workspace
-v /tmp/oc-test:/data
```

**Important**: Without `OPENCLAW_STATE_DIR=/data/.openclaw`, config defaults to `~/.openclaw` inside the container (ephemeral). On Railway, users configure this via Railway Variables.

## Build

```bash
docker build --build-arg OPENCLAW_VERSION=<version> -t oc-test .
```

Build takes ~15-20s for a fresh version, instant if layers are cached.

## Running the Container

```bash
docker run -d --name oc-test -p 9080:8080 \
  -e PORT=8080 \
  -e SETUP_PASSWORD=test123 \
  -e OPENCLAW_STATE_DIR=/data/.openclaw \
  -e OPENCLAW_WORKSPACE_DIR=/data/workspace \
  -v /tmp/oc-test:/data \
  oc-test
```

Wait ~15s for volume bootstrap on first boot. Check logs: `docker logs oc-test`

## Onboarding via API

The `/setup/api/run` endpoint requires Basic Auth with `SETUP_PASSWORD`:

```bash
curl -sf -X POST http://localhost:9080/setup/api/run \
  -H 'Content-Type: application/json' \
  -u admin:test123 \
  -d '{"flow":"quickstart","authChoice":"openai-api-key","authSecret":"sk-test-dummy-key"}'
```

Expected: `{"ok": true, ...}`. A dummy API key works — it creates the config and starts the gateway, but model calls will fail.

## Health Checks

| Endpoint | Auth | What it shows |
|----------|------|---------------|
| `/setup/healthz` | None | `{"ok":true}` — wrapper is alive |
| `/healthz` | None | `configured`, `gateway.reachable`, errors |
| `/` | Basic Auth (`admin:<SETUP_PASSWORD>`) | Proxied to gateway (200 = working, 502 = gateway dead) |
| `/openclaw` | Basic Auth | Control UI |

**Note**: `/` and `/openclaw` return **401** without Basic Auth when `SETUP_PASSWORD` is set. This is correct behavior from `requireDashboardAuth`, not a failure. Always pass `-u admin:<password>` when testing these endpoints.

## Version Upgrade Testing

To test the upgrade path:

1. Build and run with an older version (e.g., `OPENCLAW_VERSION=2026.5.28`)
2. Complete onboarding via the API
3. Stop container: `docker stop oc-test && docker rm oc-test`
4. Build with newer version (e.g., `OPENCLAW_VERSION=2026.6.1`)
5. Start new container with **same volume** (`-v /tmp/oc-test:/data`)
6. Check logs for: `[entrypoint] Image (<new>) is newer than volume (<old>). Upgrading...`
7. Verify config survived: check `/data/.openclaw/openclaw.json` still has auth profiles
8. Verify gateway starts: `/healthz` shows `configured: true` + `gateway.reachable: true`

## Key Assertions for Upgrade Tests

- Entrypoint logs must show the upgrade detection message with correct versions
- Volume `package.json` version must match the new image version
- Config file (`openclaw.json`) must be untouched (it lives in `/data/.openclaw/`, separate from `/data/openclaw/`)
- Gateway must start and respond (no 502)
- `POST /setup/api/run` should return "Already configured" (idempotent)

## Cleanup

Volume files are owned by root (from container). Use `sudo rm -rf /tmp/oc-test` to clean up.

## Config Structure

OpenClaw stores auth under `auth.profiles` (not `models.providers`). After onboarding with OpenAI:
```json
{"auth": {"profiles": {"openai:default": {"provider": "openai"}}}}
```

## Devin Secrets Needed

None required for basic testing. Dummy API keys work for onboarding verification.
