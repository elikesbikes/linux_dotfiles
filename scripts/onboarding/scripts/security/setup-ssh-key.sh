#!/bin/bash
set -euo pipefail

# Setup SSH key access on a new host using Proton Pass SSH agent.
# Requires: root SSH access to the target (Proxmox usually injects this).
# If root SSH doesn't work, use the Proxmox console — see the runbook.

DOMAIN="home.elikesbikes.com"
TARGET_USER="ecloaiza"

usage() {
    echo "Usage: $(basename "$0") <hostname>"
    echo ""
    echo "Sets up SSH key access for $TARGET_USER on a new host."
    echo "The host must have a '<hostname> SSH Key' loaded in the Proton Pass agent."
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") endurance"
    echo "  $(basename "$0") rocky"
    exit 1
}

log()  { echo "[+] $*"; }
warn() { echo "[!] $*"; }
fail() { echo "[x] $*"; exit 1; }

[[ $# -eq 1 ]] || usage
HOSTNAME="$1"
FQDN="${HOSTNAME}.${DOMAIN}"

# --- Step 1: Find the public key in the agent ---

log "Looking for '${HOSTNAME} SSH Key' in the SSH agent..."
PUBKEY=$(ssh-add -L 2>/dev/null | grep -i "${HOSTNAME} SSH Key" || true)

if [[ -z "$PUBKEY" ]]; then
    fail "No key matching '${HOSTNAME} SSH Key' found in the agent.
    Create one first:
      pass-cli login
      pass-cli item create ssh-key generate --title '${HOSTNAME} SSH Key' --vault-name HOMELAB --key-type ed25519
      systemctl --user restart proton-pass-ssh-agent"
fi

log "Found public key: ${PUBKEY:0:50}..."

# --- Step 2: Check DNS ---

log "Resolving ${FQDN}..."
if ! host "$FQDN" > /dev/null 2>&1; then
    fail "${FQDN} does not resolve. Check DNS or wait for DHCP registration."
fi

IP=$(host "$FQDN" | awk '/has address/ { print $NF; exit }')
log "Resolved to ${IP}"

# --- Step 3: Accept host key if needed ---

log "Accepting host key for ${FQDN}..."
ssh-keyscan -H "$FQDN" >> ~/.ssh/known_hosts 2>/dev/null || true

# --- Step 4: Test root SSH ---

log "Testing root SSH access..."
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "root@${FQDN}" "true" 2>/dev/null; then
    fail "Cannot SSH as root@${FQDN}.
    Proxmox didn't inject your key, or root SSH is disabled.
    Use the Proxmox console instead — see the SSH Key Setup Runbook."
fi

log "Root SSH works."

# --- Step 5: Check if user exists ---

USER_EXISTS=$(ssh -o BatchMode=yes "root@${FQDN}" "id ${TARGET_USER} 2>/dev/null && echo yes || echo no")

if [[ "$USER_EXISTS" == "no" ]]; then
    log "User ${TARGET_USER} does not exist. Creating..."
    ssh -o BatchMode=yes "root@${FQDN}" bash <<REMOTE
        useradd -m -s /bin/bash ${TARGET_USER}
        usermod -aG sudo ${TARGET_USER}
        echo "${TARGET_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${TARGET_USER}
        chmod 440 /etc/sudoers.d/${TARGET_USER}
REMOTE
    log "User ${TARGET_USER} created with passwordless sudo."
else
    log "User ${TARGET_USER} already exists."

    # Check if sudo is set up
    SUDO_FILE=$(ssh -o BatchMode=yes "root@${FQDN}" "test -f /etc/sudoers.d/${TARGET_USER} && echo yes || echo no")
    if [[ "$SUDO_FILE" == "no" ]]; then
        log "Setting up passwordless sudo..."
        ssh -o BatchMode=yes "root@${FQDN}" bash <<REMOTE
            usermod -aG sudo ${TARGET_USER}
            echo "${TARGET_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${TARGET_USER}
            chmod 440 /etc/sudoers.d/${TARGET_USER}
REMOTE
        log "Sudo configured."
    else
        log "Sudo already configured."
    fi
fi

# --- Step 6: Install the SSH key ---

KEY_INSTALLED=$(ssh -o BatchMode=yes "root@${FQDN}" \
    "grep -qF '${PUBKEY}' /home/${TARGET_USER}/.ssh/authorized_keys 2>/dev/null && echo yes || echo no")

if [[ "$KEY_INSTALLED" == "yes" ]]; then
    log "Key already installed for ${TARGET_USER}."
else
    log "Installing SSH key for ${TARGET_USER}..."
    echo "$PUBKEY" | ssh -o BatchMode=yes "root@${FQDN}" bash <<REMOTE
        mkdir -p /home/${TARGET_USER}/.ssh
        chmod 700 /home/${TARGET_USER}/.ssh
        cat >> /home/${TARGET_USER}/.ssh/authorized_keys
        chmod 600 /home/${TARGET_USER}/.ssh/authorized_keys
        chown -R ${TARGET_USER}:${TARGET_USER} /home/${TARGET_USER}/.ssh
REMOTE
    log "Key installed."
fi

# --- Step 7: Test ecloaiza SSH ---

log "Testing SSH as ${TARGET_USER}..."
if ssh -o ConnectTimeout=5 -o BatchMode=yes "${TARGET_USER}@${FQDN}" "true" 2>/dev/null; then
    log "SSH as ${TARGET_USER} works."
else
    warn "SSH as ${TARGET_USER} failed. Likely a MaxAuthTries issue (too many keys in the agent)."
    warn "Creating pubkey file and SSH config entry..."

    mkdir -p ~/.ssh/pubkeys
    echo "$PUBKEY" > ~/.ssh/pubkeys/${HOSTNAME}.pub

    if ! grep -q "^Host ${HOSTNAME}$" ~/.ssh/config 2>/dev/null; then
        cat >> ~/.ssh/config <<EOF

Host ${HOSTNAME}
    HostName ${FQDN}
    User ${TARGET_USER}
    IdentityFile ~/.ssh/pubkeys/${HOSTNAME}.pub
    IdentitiesOnly yes
EOF
        log "Added SSH config entry for ${HOSTNAME}."
    else
        warn "SSH config entry for ${HOSTNAME} already exists — check it manually."
    fi

    if ssh -o ConnectTimeout=5 -o BatchMode=yes "${HOSTNAME}" "true" 2>/dev/null; then
        log "SSH via config alias works."
    else
        fail "Still can't connect. Debug manually:
      ssh -v ${TARGET_USER}@${FQDN}"
    fi
fi

# --- Step 8: Final verification ---

RESULT=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "${TARGET_USER}@${FQDN}" "whoami && sudo whoami" 2>/dev/null || \
         ssh -o ConnectTimeout=5 -o BatchMode=yes "${HOSTNAME}" "whoami && sudo whoami" 2>/dev/null || \
         echo "FAILED")

if [[ "$RESULT" == *"FAILED"* ]]; then
    fail "Final verification failed."
fi

echo ""
echo "=== Done ==="
echo "Host:   ${FQDN} (${IP})"
echo "User:   ${TARGET_USER}"
echo "Key:    ${HOSTNAME} SSH Key"
echo "SSH:    ssh ${TARGET_USER}@${FQDN}"
echo ""
echo "Next steps:"
echo "  - Update Proton Pass PAT Setup doc (PAT Storage table + SSH Keys list)"
echo "  - (Optional) Seal a TPM PAT on ${HOSTNAME} if it needs pass-cli"
