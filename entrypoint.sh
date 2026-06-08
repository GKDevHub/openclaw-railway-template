#!/usr/bin/env bash
set -e

# ---------------------------------------------------------------------------
# OpenClaw volume bootstrap
#
# The Docker image ships a "seed" OpenClaw version at the standard npm global
# path (/usr/local/lib/node_modules/openclaw).  On first boot we install the
# same version to the Railway persistent volume (/data/openclaw) so that
# `openclaw update` can modify it in-place and the change survives container
# restarts.  On subsequent boots the volume copy is reused as-is.
#
# When the image is rebuilt with a newer OPENCLAW_VERSION the entrypoint
# detects the version gap and auto-upgrades the volume (never downgrades,
# so a user-initiated `openclaw update` to a newer release is preserved).
# ---------------------------------------------------------------------------

IMAGE_ENTRY=/usr/local/lib/node_modules/openclaw/dist/entry.js
VOLUME_DIR=/data/openclaw
VOLUME_ENTRY=$VOLUME_DIR/node_modules/openclaw/dist/entry.js

# Read version from package.json (fast, no child process).
read_version() {
  node -e "process.stdout.write(require('$1/package.json').version)"
}

IMAGE_VER=$(read_version /usr/local/lib/node_modules/openclaw)

install_to_volume() {
  echo "[entrypoint] Installing OpenClaw $IMAGE_VER to volume..."
  # Clear NPM_CONFIG_PREFIX for this install so npm writes to /data/openclaw
  # (the --prefix flag), not to /data/npm.
  NPM_CONFIG_PREFIX= npm install --prefix "$VOLUME_DIR" \
    --no-audit --no-fund "openclaw@${IMAGE_VER}" 2>&1
  # Provide an `openclaw` CLI shim on the volume so PATH lookup works.
  mkdir -p "$VOLUME_DIR/bin"
  printf '%s\n' '#!/usr/bin/env bash' \
    "exec node $VOLUME_ENTRY \"\$@\"" > "$VOLUME_DIR/bin/openclaw"
  chmod +x "$VOLUME_DIR/bin/openclaw"
  echo "[entrypoint] OpenClaw $IMAGE_VER installed to volume."
}

# Returns 0 (true) when $1 > $2 using dot-separated numeric comparison.
version_gt() {
  local IFS=.
  # shellcheck disable=SC2206
  local a=($1) b=($2)
  for i in 0 1 2; do
    local ai=${a[i]:-0} bi=${b[i]:-0}
    if (( ai > bi )); then return 0; fi
    if (( ai < bi )); then return 1; fi
  done
  return 1  # equal
}

if [ ! -f "$VOLUME_ENTRY" ]; then
  # First boot: no openclaw on volume yet.
  install_to_volume
else
  VOLUME_VER=$(read_version "$VOLUME_DIR/node_modules/openclaw" 2>/dev/null || echo "0.0.0")
  if version_gt "$IMAGE_VER" "$VOLUME_VER"; then
    echo "[entrypoint] Image ($IMAGE_VER) is newer than volume ($VOLUME_VER). Upgrading..."
    install_to_volume
  else
    echo "[entrypoint] Volume OpenClaw $VOLUME_VER is up to date."
  fi
fi

# Tell the wrapper to use the volume install.
export OPENCLAW_ENTRY="$VOLUME_ENTRY"

# Also put the volume openclaw shim on PATH (ahead of /usr/local/bin) so
# `openclaw update` detects the volume root and updates there.
export PATH="$VOLUME_DIR/bin:$PATH"

exec node src/server.js
