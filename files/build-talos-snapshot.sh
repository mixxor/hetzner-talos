#!/bin/bash
# Creates a Talos Linux snapshot on Hetzner Cloud.
# Called by terraform_data.talos_snapshot via local-exec.
#
# Required env vars: HCLOUD_TOKEN, TALOS_VERSION, IMAGE_URL, LOCATION
set -euo pipefail

: "${HCLOUD_TOKEN:?must be set}"
: "${TALOS_VERSION:?must be set}"
: "${IMAGE_URL:?must be set}"
: "${LOCATION:?must be set}"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

# Track resources for cleanup
SERVER_ID=""
SSH_KEY_ID=""
SSH_KEY_FILE=""

cleanup() {
    if [[ -n "$SERVER_ID" ]]; then
        echo "Cleaning up builder server ${SERVER_ID}..."
        hcloud server delete "$SERVER_ID" 2>/dev/null || true
    fi
    if [[ -n "$SSH_KEY_ID" ]]; then
        hcloud ssh-key delete "$SSH_KEY_ID" 2>/dev/null || true
    fi
    if [[ -n "$SSH_KEY_FILE" ]]; then
        rm -f "$SSH_KEY_FILE" "${SSH_KEY_FILE}.pub"
    fi
}
trap cleanup EXIT

# --- Idempotency: skip if snapshot already exists ---

existing=$(hcloud image list -o json \
    | jq -r ".[] | select(.labels.\"talos-version\" == \"${TALOS_VERSION}\") | .id" \
    | head -1)

if [[ -n "$existing" ]]; then
    echo "Talos snapshot already exists (ID: ${existing}), skipping."
    exit 0
fi

echo "Building Talos ${TALOS_VERSION} snapshot..."

# --- Temporary SSH key ---

SSH_KEY_FILE="/tmp/talos-builder-key-$$"
rm -f "$SSH_KEY_FILE" "${SSH_KEY_FILE}.pub"
ssh-keygen -t ed25519 -f "$SSH_KEY_FILE" -N "" -q

SSH_KEY_ID=$(hcloud ssh-key create \
    --name "talos-builder-$(date +%s)" \
    --public-key-from-file "${SSH_KEY_FILE}.pub" \
    -o json | jq -r '.ssh_key.id')

# --- Builder server ---

echo "Creating builder server in ${LOCATION}..."
server_info=$(hcloud server create \
    --name "talos-builder-$(date +%s)" \
    --type cx33 \
    --image debian-12 \
    --location "$LOCATION" \
    --ssh-key "$SSH_KEY_ID" \
    -o json)

SERVER_ID=$(echo "$server_info" | jq -r '.server.id')
server_ip=$(echo "$server_info" | jq -r '.server.public_net.ipv4.ip')

if [[ -z "$SERVER_ID" || "$SERVER_ID" == "null" ]]; then
    echo "ERROR: Failed to create builder server" >&2
    exit 1
fi

echo "Builder server: ${server_ip} (ID: ${SERVER_ID})"

# --- Rescue mode ---

echo "Enabling rescue mode..."
hcloud server enable-rescue "$SERVER_ID" --ssh-key "$SSH_KEY_ID" >/dev/null
hcloud server reboot "$SERVER_ID" >/dev/null

echo "Waiting for rescue mode..."
sleep 30
for i in {1..30}; do
    ssh $SSH_OPTS -o ConnectTimeout=5 -i "$SSH_KEY_FILE" root@"$server_ip" \
        'echo ready' 2>/dev/null && break
    echo -n "."
    sleep 5
done
echo ""

# --- Download and write image ---

echo "Downloading and writing Talos image on server..."
ssh $SSH_OPTS -i "$SSH_KEY_FILE" root@"$server_ip" bash -s -- "$IMAGE_URL" <<'REMOTE_SCRIPT'
    set -euo pipefail
    IMAGE_URL="$1"

    echo "Downloading Talos image..."
    curl -fSL --retry 3 -o /tmp/talos.raw.xz "$IMAGE_URL"

    echo "Verifying download..."
    xz -t /tmp/talos.raw.xz
    echo "Image verified ($(stat -c%s /tmp/talos.raw.xz) bytes compressed)"

    echo "Wiping disk..."
    wipefs -a /dev/sda 2>/dev/null || true
    dd if=/dev/zero of=/dev/sda bs=1M count=100 2>/dev/null || true

    echo "Decompressing and writing Talos to disk..."
    xz -dc /tmp/talos.raw.xz | dd of=/dev/sda bs=4M conv=fsync status=progress

    # conv=fsync flushes each block. Don't run standalone sync after —
    # overwriting /dev/sda breaks rescue-mode binary resolution.
    echo "Write complete!"
REMOTE_SCRIPT

# --- Snapshot ---

echo "Powering off builder server..."
hcloud server poweroff "$SERVER_ID" >/dev/null 2>&1 || true
sleep 10

echo "Creating snapshot..."
snapshot_output=$(hcloud server create-image "$SERVER_ID" \
    --type snapshot \
    --description "Talos Linux ${TALOS_VERSION}" 2>&1)

snapshot_id=$(echo "$snapshot_output" | grep -oE 'Image [0-9]+' | awk '{print $2}')
if [[ -z "$snapshot_id" ]]; then
    echo "ERROR: Failed to create snapshot: ${snapshot_output}" >&2
    exit 1
fi

hcloud image add-label "$snapshot_id" "talos-version=${TALOS_VERSION}"

echo "Talos snapshot created (ID: ${snapshot_id})"
