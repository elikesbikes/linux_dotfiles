#!/bin/bash
set -euo pipefail

# Setup SSH key access on a new host using Proton Pass SSH agent.
# Supports: Ubuntu, Arch, Windows (OpenSSH). LXC, VM, or bare metal.
# If SSH doesn't work at all, use the console — see the SSH Key Setup Runbook.

DOMAIN="home.elikesbikes.com"
TARGET_USER="ecloaiza"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <hostname>

Sets up SSH key access for ${TARGET_USER} on a new host.
The host must have a '<hostname> SSH Key' loaded in the Proton Pass agent.

Options:
  --user <login_user>   User to SSH in as for setup (default: root)
  --password            Allow password prompt on initial SSH (for non-Proxmox hosts)
  --windows             Target is a Windows host (OpenSSH)
  --ip <address>        Use IP directly instead of <hostname>.${DOMAIN}

Examples:
  $(basename "$0") endurance                        # Proxmox LXC, root key injected
  $(basename "$0") --password endurance              # Fresh machine, need password
  $(basename "$0") --password --user admin kipp      # SSH as admin first
  $(basename "$0") --windows --password nvr-prod-1   # Windows host
  $(basename "$0") --ip 192.168.5.50 newbox          # Use IP, key name is 'newbox SSH Key'
EOF
    exit 1
}

log()  { echo "[+] $*"; }
warn() { echo "[!] $*"; }
fail() { echo "[x] $*"; exit 1; }

LOGIN_USER="root"
ALLOW_PASSWORD=false
IS_WINDOWS=false
CUSTOM_IP=""
HOSTNAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --user) LOGIN_USER="$2"; shift 2 ;;
        --password) ALLOW_PASSWORD=true; shift ;;
        --windows) IS_WINDOWS=true; shift ;;
        --ip) CUSTOM_IP="$2"; shift 2 ;;
        --help|-h) usage ;;
        -*) fail "Unknown option: $1" ;;
        *) HOSTNAME="$1"; shift ;;
    esac
done

[[ -n "$HOSTNAME" ]] || usage

if [[ -n "$CUSTOM_IP" ]]; then
    FQDN="$CUSTOM_IP"
else
    FQDN="${HOSTNAME}.${DOMAIN}"
fi

# SSH multiplexing — reuse a single connection so password is only entered once.
CONTROL_DIR=$(mktemp -d)
CONTROL_PATH="${CONTROL_DIR}/ssh-%r@%h:%p"

cleanup() {
    ssh -o ControlPath="$CONTROL_PATH" -O exit "${LOGIN_USER}@${FQDN}" 2>/dev/null || true
    rm -rf "$CONTROL_DIR"
}
trap cleanup EXIT

SSH_OPTS="-o ConnectTimeout=10 -o ControlMaster=auto -o ControlPath=${CONTROL_PATH} -o ControlPersist=120"
if [[ "$ALLOW_PASSWORD" == false ]]; then
    SSH_OPTS="$SSH_OPTS -o BatchMode=yes"
else
    # Bypass the agent entirely — too many keys triggers MaxAuthTries before
    # the password prompt. Force keyboard-interactive/password only.
    SSH_OPTS="$SSH_OPTS -o IdentitiesOnly=yes -o PreferredAuthentications=keyboard-interactive,password"
fi

ssh_cmd() {
    ssh $SSH_OPTS "$@"
}

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

# --- Step 2: Check DNS / connectivity ---

log "Checking connectivity to ${FQDN}..."
if [[ -z "$CUSTOM_IP" ]]; then
    if ! host "$FQDN" > /dev/null 2>&1; then
        fail "${FQDN} does not resolve. Check DNS or wait for DHCP registration."
    fi
    IP=$(host "$FQDN" | awk '/has address/ { print $NF; exit }')
else
    IP="$CUSTOM_IP"
fi
log "Target: ${IP}"

# --- Step 3: Accept host key if needed ---

log "Accepting host key for ${FQDN}..."
ssh-keyscan -H "$FQDN" >> ~/.ssh/known_hosts 2>/dev/null || true

# --- Step 4: Test initial SSH and open master connection ---

log "Connecting as ${LOGIN_USER}@${FQDN}..."
if [[ "$ALLOW_PASSWORD" == true ]]; then
    log "Password prompt will appear — enter the password for ${LOGIN_USER}."
    log "(You only need to enter it once.)"
fi

if ! ssh_cmd "${LOGIN_USER}@${FQDN}" "echo ok" > /dev/null; then
    if [[ "$ALLOW_PASSWORD" == false ]]; then
        fail "Cannot SSH as ${LOGIN_USER}@${FQDN} (key auth failed).
    Try again with --password if the host requires a password."
    else
        fail "Cannot SSH as ${LOGIN_USER}@${FQDN}.
    Check: is SSH running? Is the username correct? Can you reach the host?"
    fi
fi

log "Connected. Master connection established."

# --- Step 5: Detect OS ---

if [[ "$IS_WINDOWS" == true ]]; then
    DETECTED_OS="windows"
    log "Target OS: Windows (manual flag)"
else
    DETECTED_OS=$(ssh_cmd "${LOGIN_USER}@${FQDN}" "uname -s 2>/dev/null || echo unknown" | tr '[:upper:]' '[:lower:]')
    if [[ "$DETECTED_OS" == *"mingw"* ]] || [[ "$DETECTED_OS" == *"msys"* ]] || [[ "$DETECTED_OS" == *"cygwin"* ]]; then
        DETECTED_OS="windows"
    fi

    if [[ "$DETECTED_OS" == "linux" ]]; then
        DISTRO=$(ssh_cmd "${LOGIN_USER}@${FQDN}" "grep -oP '^ID=\K.*' /etc/os-release 2>/dev/null | tr -d '\"'" || true)
        log "Target OS: Linux (${DISTRO:-unknown distro})"
    else
        log "Target OS: ${DETECTED_OS}"
    fi
fi

# --- Windows path ---

if [[ "$DETECTED_OS" == "windows" ]]; then
    log "Setting up SSH key on Windows host..."

    # Check if user exists
    USER_HOME=$(ssh_cmd "${LOGIN_USER}@${FQDN}" \
        "powershell -Command \"(Get-LocalUser '${TARGET_USER}' -ErrorAction SilentlyContinue) -and (Test-Path C:\\Users\\${TARGET_USER}) | Write-Output\"" 2>/dev/null || echo "")

    if [[ "$USER_HOME" != *"True"* ]]; then
        warn "User ${TARGET_USER} may not exist on Windows. Checking home directory..."
        HAS_HOME=$(ssh_cmd "${LOGIN_USER}@${FQDN}" "powershell -Command \"Test-Path C:\\Users\\${TARGET_USER}\"" 2>/dev/null || echo "False")
        if [[ "$HAS_HOME" != "True" ]]; then
            fail "User ${TARGET_USER} does not exist on this Windows host.
    Create the user manually in Windows Settings or via:
      net user ${TARGET_USER} /add
      net localgroup Administrators ${TARGET_USER} /add"
        fi
    fi

    IS_ADMIN=$(ssh_cmd "${LOGIN_USER}@${FQDN}" \
        "powershell -Command \"(Get-LocalGroupMember Administrators | Where-Object Name -match '${TARGET_USER}') -ne \\\$null\"" 2>/dev/null || echo "False")

    if [[ "$IS_ADMIN" == "True" ]]; then
        log "User is an administrator — key goes in administrators_authorized_keys."
        KEY_FILE="C:\\ProgramData\\ssh\\administrators_authorized_keys"

        KEY_INSTALLED=$(ssh_cmd "${LOGIN_USER}@${FQDN}" \
            "powershell -Command \"if (Test-Path '${KEY_FILE}') { (Get-Content '${KEY_FILE}' | Select-String -SimpleMatch '${PUBKEY}' -Quiet) } else { 'False' }\"" 2>/dev/null || echo "False")

        if [[ "$KEY_INSTALLED" == "True" ]]; then
            log "Key already installed."
        else
            log "Installing key to ${KEY_FILE}..."
            ssh_cmd "${LOGIN_USER}@${FQDN}" "powershell -Command \"
                Add-Content -Path '${KEY_FILE}' -Value '${PUBKEY}'
                icacls '${KEY_FILE}' /inheritance:r /grant 'SYSTEM:(R)' /grant 'BUILTIN\\Administrators:(R)'
            \""
            log "Key installed."
        fi
    else
        log "User is not an administrator — key goes in user .ssh directory."
        KEY_FILE="C:\\Users\\${TARGET_USER}\\.ssh\\authorized_keys"

        KEY_INSTALLED=$(ssh_cmd "${LOGIN_USER}@${FQDN}" \
            "powershell -Command \"if (Test-Path '${KEY_FILE}') { (Get-Content '${KEY_FILE}' | Select-String -SimpleMatch '${PUBKEY}' -Quiet) } else { 'False' }\"" 2>/dev/null || echo "False")

        if [[ "$KEY_INSTALLED" == "True" ]]; then
            log "Key already installed."
        else
            log "Installing key to ${KEY_FILE}..."
            ssh_cmd "${LOGIN_USER}@${FQDN}" "powershell -Command \"
                New-Item -ItemType Directory -Force -Path 'C:\\Users\\${TARGET_USER}\\.ssh' | Out-Null
                Add-Content -Path '${KEY_FILE}' -Value '${PUBKEY}'
                icacls '${KEY_FILE}' /inheritance:r /grant '${TARGET_USER}:(R)' /grant 'SYSTEM:(R)'
            \""
            log "Key installed."
        fi
    fi

    # Close master connection before testing as target user
    ssh -o ControlPath="$CONTROL_PATH" -O exit "${LOGIN_USER}@${FQDN}" 2>/dev/null || true

    # Test as target user using only the correct key
    log "Testing SSH as ${TARGET_USER}..."
    mkdir -p ~/.ssh/pubkeys
    echo "$PUBKEY" > ~/.ssh/pubkeys/${HOSTNAME}.pub

    if ssh -o ConnectTimeout=5 -o BatchMode=yes -o IdentitiesOnly=yes -i ~/.ssh/pubkeys/${HOSTNAME}.pub "${TARGET_USER}@${FQDN}" "echo ok" > /dev/null 2>&1; then
        log "SSH as ${TARGET_USER} works."
    else
        warn "SSH as ${TARGET_USER} failed with direct key. Adding SSH config entry..."
        if ! grep -q "^Host ${HOSTNAME}$" ~/.ssh/config 2>/dev/null; then
            cat >> ~/.ssh/config <<EOF

Host ${HOSTNAME}
    HostName ${FQDN}
    User ${TARGET_USER}
    IdentityFile ~/.ssh/pubkeys/${HOSTNAME}.pub
    IdentitiesOnly yes
EOF
            log "Added SSH config entry for ${HOSTNAME}."
        fi

        if ssh -o ConnectTimeout=5 -o BatchMode=yes "${HOSTNAME}" "echo ok" > /dev/null 2>&1; then
            log "SSH via config alias works."
        else
            fail "Still can't connect. Debug: ssh -v ${TARGET_USER}@${FQDN}"
        fi
    fi

    echo ""
    echo "=== Done (Windows) ==="
    echo "Host:   ${FQDN} (${IP})"
    echo "User:   ${TARGET_USER}"
    echo "Key:    ${HOSTNAME} SSH Key"
    echo "SSH:    ssh ${TARGET_USER}@${FQDN}"
    exit 0
fi

# --- Linux path ---

# --- Step 6: Check if user exists ---

USER_EXISTS=$(ssh_cmd "${LOGIN_USER}@${FQDN}" "id ${TARGET_USER} 2>/dev/null && echo yes || echo no")

if [[ "$USER_EXISTS" == "no" ]]; then
    log "User ${TARGET_USER} does not exist. Creating..."

    SUDO_GROUP="sudo"
    if [[ "${DISTRO:-}" == "arch" ]]; then
        SUDO_GROUP="wheel"
    fi

    ssh_cmd "${LOGIN_USER}@${FQDN}" bash <<REMOTE
        useradd -m -s /bin/bash ${TARGET_USER}
        usermod -aG ${SUDO_GROUP} ${TARGET_USER}
        echo "${TARGET_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${TARGET_USER}
        chmod 440 /etc/sudoers.d/${TARGET_USER}
REMOTE
    log "User ${TARGET_USER} created with passwordless sudo (group: ${SUDO_GROUP})."
else
    log "User ${TARGET_USER} already exists."

    SUDO_FILE=$(ssh_cmd "${LOGIN_USER}@${FQDN}" "test -f /etc/sudoers.d/${TARGET_USER} && echo yes || echo no")
    if [[ "$SUDO_FILE" == "no" ]]; then
        SUDO_GROUP="sudo"
        if [[ "${DISTRO:-}" == "arch" ]]; then
            SUDO_GROUP="wheel"
        fi

        log "Setting up passwordless sudo (group: ${SUDO_GROUP})..."
        ssh_cmd "${LOGIN_USER}@${FQDN}" bash <<REMOTE
            usermod -aG ${SUDO_GROUP} ${TARGET_USER}
            echo "${TARGET_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${TARGET_USER}
            chmod 440 /etc/sudoers.d/${TARGET_USER}
REMOTE
        log "Sudo configured."
    else
        log "Sudo already configured."
    fi
fi

# --- Step 7: Install the SSH key ---

TARGET_HOME=$(ssh_cmd "${LOGIN_USER}@${FQDN}" "eval echo ~${TARGET_USER}")

KEY_INSTALLED=$(ssh_cmd "${LOGIN_USER}@${FQDN}" \
    "grep -qF '${PUBKEY}' ${TARGET_HOME}/.ssh/authorized_keys 2>/dev/null && echo yes || echo no")

if [[ "$KEY_INSTALLED" == "yes" ]]; then
    log "Key already installed for ${TARGET_USER}."
else
    log "Installing SSH key for ${TARGET_USER}..."
    ssh_cmd "${LOGIN_USER}@${FQDN}" "mkdir -p ${TARGET_HOME}/.ssh && chmod 700 ${TARGET_HOME}/.ssh && echo '${PUBKEY}' >> ${TARGET_HOME}/.ssh/authorized_keys && chmod 600 ${TARGET_HOME}/.ssh/authorized_keys && chown -R ${TARGET_USER}:${TARGET_USER} ${TARGET_HOME}/.ssh"
    log "Key installed."
fi

# --- Step 8: Test ecloaiza SSH ---

# Close master connection before testing as target user
ssh -o ControlPath="$CONTROL_PATH" -O exit "${LOGIN_USER}@${FQDN}" 2>/dev/null || true

# Save pubkey to file for direct key auth (avoids MaxAuthTries)
mkdir -p ~/.ssh/pubkeys
echo "$PUBKEY" > ~/.ssh/pubkeys/${HOSTNAME}.pub

log "Testing SSH as ${TARGET_USER}..."
if ssh -o ConnectTimeout=5 -o BatchMode=yes -o IdentitiesOnly=yes -i ~/.ssh/pubkeys/${HOSTNAME}.pub "${TARGET_USER}@${FQDN}" "true" 2>/dev/null; then
    log "SSH as ${TARGET_USER} works."
else
    warn "SSH as ${TARGET_USER} failed with direct key. Adding SSH config entry..."

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
        fail "Still can't connect. Debug: ssh -v ${TARGET_USER}@${FQDN}"
    fi
fi

# --- Step 9: Final verification ---

RESULT=$(ssh -o ConnectTimeout=5 -o BatchMode=yes -o IdentitiesOnly=yes -i ~/.ssh/pubkeys/${HOSTNAME}.pub "${TARGET_USER}@${FQDN}" "whoami && sudo whoami" 2>/dev/null || \
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
echo "Pubkey: ~/.ssh/pubkeys/${HOSTNAME}.pub"
echo "OS:     ${DETECTED_OS} (${DISTRO:-n/a})"
echo "SSH:    ssh ${TARGET_USER}@${FQDN}"
echo ""
echo "Next steps:"
echo "  - Update Proton Pass PAT Setup doc (PAT Storage table + SSH Keys list)"
echo "  - (Optional) Seal a TPM PAT on ${HOSTNAME} if it needs pass-cli"
