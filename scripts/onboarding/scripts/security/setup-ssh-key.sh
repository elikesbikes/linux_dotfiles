#!/bin/bash
set -uo pipefail

# Setup SSH key access on a new host using Proton Pass SSH agent.
# Supports: Ubuntu, Debian, Arch, Proxmox, Windows (OpenSSH).
# LXC, VM, or bare metal.

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
err()  { echo "[x] $*"; }

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
        -*) err "Unknown option: $1"; usage ;;
        *) HOSTNAME="$1"; shift ;;
    esac
done

[[ -n "$HOSTNAME" ]] || usage

if [[ -n "$CUSTOM_IP" ]]; then
    FQDN="$CUSTOM_IP"
else
    FQDN="${HOSTNAME}.${DOMAIN}"
fi

# --- SSH multiplexing setup ---
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
    SSH_OPTS="$SSH_OPTS -o IdentitiesOnly=yes -o PreferredAuthentications=keyboard-interactive,password"
fi

ssh_cmd() {
    ssh $SSH_OPTS "$@"
}

# Run a command on the remote host as root.
# If login user is root, run directly. Otherwise, prefix with sudo.
ssh_root() {
    local cmd="$1"
    if [[ "$LOGIN_USER" == "root" ]]; then
        ssh_cmd "${LOGIN_USER}@${FQDN}" "$cmd"
    else
        ssh_cmd "${LOGIN_USER}@${FQDN}" "sudo $cmd"
    fi
}

# Track what we did for the summary
DID_CREATE_USER=false
DID_INSTALL_SUDO=false
DID_CONFIGURE_SUDO=false
DID_INSTALL_KEY=false
DID_ADD_SSH_CONFIG=false
HAS_SUDO=false
DETECTED_OS="unknown"
DISTRO=""

# ============================================================
# Step 1: Find the public key in the agent
# ============================================================

log "Looking for '${HOSTNAME} SSH Key' in the SSH agent..."
PUBKEY=$(ssh-add -L 2>/dev/null | grep -i "${HOSTNAME} SSH Key" || true)

if [[ -z "$PUBKEY" ]]; then
    err "No key matching '${HOSTNAME} SSH Key' found in the agent."
    echo ""
    echo "Create one first:"
    echo "  pass-cli login"
    echo "  pass-cli item create ssh-key generate --title '${HOSTNAME} SSH Key' --vault-name HOMELAB --key-type ed25519"
    echo "  systemctl --user restart proton-pass-ssh-agent"
    exit 1
fi

log "Found public key: ${PUBKEY:0:50}..."

# Save pubkey to file now — we'll need it for testing later regardless
mkdir -p ~/.ssh/pubkeys
echo "$PUBKEY" > ~/.ssh/pubkeys/${HOSTNAME}.pub

# ============================================================
# Step 2: Check DNS / connectivity
# ============================================================

log "Checking connectivity to ${FQDN}..."
if [[ -z "$CUSTOM_IP" ]]; then
    if ! host "$FQDN" > /dev/null 2>&1; then
        err "${FQDN} does not resolve."
        echo "Check DNS or wait for DHCP registration, or use --ip <address>."
        exit 1
    fi
    IP=$(host "$FQDN" | awk '/has address/ { print $NF; exit }')
else
    IP="$CUSTOM_IP"
fi
log "Target: ${IP}"

# ============================================================
# Step 3: Accept host key
# ============================================================

log "Accepting host key for ${FQDN}..."
ssh-keyscan -H "$FQDN" >> ~/.ssh/known_hosts 2>/dev/null || true

# ============================================================
# Step 4: Open master connection
# ============================================================

log "Connecting as ${LOGIN_USER}@${FQDN}..."
if [[ "$ALLOW_PASSWORD" == true ]]; then
    log "Password prompt will appear — enter the password for ${LOGIN_USER}."
    log "(You only need to enter it once.)"
fi

if ! ssh_cmd "${LOGIN_USER}@${FQDN}" "echo ok" > /dev/null; then
    err "Cannot SSH as ${LOGIN_USER}@${FQDN}."
    if [[ "$ALLOW_PASSWORD" == false ]]; then
        echo "Key auth failed. Try again with --password if the host requires a password."
    else
        echo "Check: is SSH running? Is the username correct? Can you reach the host?"
    fi
    exit 1
fi

log "Connected. Master connection established."

# ============================================================
# Step 5: Detect OS
# ============================================================

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

# ============================================================
# Windows path
# ============================================================

if [[ "$DETECTED_OS" == "windows" ]]; then
    log "Setting up SSH key on Windows host..."

    HAS_HOME=$(ssh_cmd "${LOGIN_USER}@${FQDN}" "powershell -Command \"Test-Path C:\\Users\\${TARGET_USER}\"" 2>/dev/null || echo "False")
    if [[ "$HAS_HOME" != "True" ]]; then
        err "User ${TARGET_USER} does not exist on this Windows host."
        echo "Create the user manually:"
        echo "  net user ${TARGET_USER} <password> /add"
        echo "  net localgroup Administrators ${TARGET_USER} /add"
        exit 1
    fi

    IS_ADMIN=$(ssh_cmd "${LOGIN_USER}@${FQDN}" \
        "powershell -Command \"try { \\\$null -ne (Get-LocalGroupMember Administrators | Where-Object Name -match '${TARGET_USER}') } catch { 'False' }\"" 2>/dev/null || echo "False")

    if [[ "$IS_ADMIN" == "True" ]]; then
        log "User is an administrator — key goes in administrators_authorized_keys."
        KEY_FILE="C:\\ProgramData\\ssh\\administrators_authorized_keys"
        INSTALL_CMD="Add-Content -Path '${KEY_FILE}' -Value '${PUBKEY}'; icacls '${KEY_FILE}' /inheritance:r /grant 'SYSTEM:(R)' /grant 'BUILTIN\\Administrators:(R)'"
    else
        log "User is not an administrator — key goes in user .ssh directory."
        KEY_FILE="C:\\Users\\${TARGET_USER}\\.ssh\\authorized_keys"
        INSTALL_CMD="New-Item -ItemType Directory -Force -Path 'C:\\Users\\${TARGET_USER}\\.ssh' | Out-Null; Add-Content -Path '${KEY_FILE}' -Value '${PUBKEY}'; icacls '${KEY_FILE}' /inheritance:r /grant '${TARGET_USER}:(R)' /grant 'SYSTEM:(R)'"
    fi

    KEY_INSTALLED=$(ssh_cmd "${LOGIN_USER}@${FQDN}" \
        "powershell -Command \"if (Test-Path '${KEY_FILE}') { (Get-Content '${KEY_FILE}' | Select-String -SimpleMatch '$(echo "$PUBKEY" | awk '{print $2}')' -Quiet) } else { 'False' }\"" 2>/dev/null || echo "False")

    if [[ "$KEY_INSTALLED" == "True" ]]; then
        log "Key already installed."
    else
        log "Installing key..."
        ssh_cmd "${LOGIN_USER}@${FQDN}" "powershell -Command \"${INSTALL_CMD}\""
        DID_INSTALL_KEY=true
        log "Key installed."
    fi

    # Close master, test as target user
    ssh -o ControlPath="$CONTROL_PATH" -O exit "${LOGIN_USER}@${FQDN}" 2>/dev/null || true

    log "Testing SSH as ${TARGET_USER}..."
    if ssh -o ConnectTimeout=5 -o BatchMode=yes -o IdentitiesOnly=yes -i ~/.ssh/pubkeys/${HOSTNAME}.pub "${TARGET_USER}@${FQDN}" "echo ok" > /dev/null 2>&1; then
        log "SSH as ${TARGET_USER} works."
    else
        warn "Direct key test failed. Adding SSH config entry..."
        if ! grep -q "^Host ${HOSTNAME}$" ~/.ssh/config 2>/dev/null; then
            cat >> ~/.ssh/config <<EOF

Host ${HOSTNAME}
    HostName ${FQDN}
    User ${TARGET_USER}
    IdentityFile ~/.ssh/pubkeys/${HOSTNAME}.pub
    IdentitiesOnly yes
EOF
            DID_ADD_SSH_CONFIG=true
            log "Added SSH config entry."
        fi

        if ssh -o ConnectTimeout=5 -o BatchMode=yes "${HOSTNAME}" "echo ok" > /dev/null 2>&1; then
            log "SSH via config alias works."
        else
            err "Cannot connect as ${TARGET_USER}. Debug: ssh -v ${TARGET_USER}@${FQDN}"
            exit 1
        fi
    fi

    echo ""
    echo "=== Done (Windows) ==="
    echo "Host:   ${FQDN} (${IP})"
    echo "User:   ${TARGET_USER}"
    echo "Key:    ${HOSTNAME} SSH Key"
    echo "Pubkey: ~/.ssh/pubkeys/${HOSTNAME}.pub"
    echo "SSH:    ssh ${TARGET_USER}@${FQDN}"
    exit 0
fi

# ============================================================
# Linux path
# ============================================================

# --- Step 6: Check / create user ---

USER_EXISTS=$(ssh_cmd "${LOGIN_USER}@${FQDN}" "id ${TARGET_USER} > /dev/null 2>&1 && echo yes || echo no")

if [[ "$USER_EXISTS" == "no" ]]; then
    log "User ${TARGET_USER} does not exist. Creating..."
    ssh_root "useradd -m -s /bin/bash ${TARGET_USER}"
    DID_CREATE_USER=true
    log "User ${TARGET_USER} created."
else
    log "User ${TARGET_USER} already exists."
fi

# --- Step 7: Install sudo if missing, configure if needed ---

HAS_SUDO_BIN=$(ssh_cmd "${LOGIN_USER}@${FQDN}" "command -v sudo > /dev/null 2>&1 && echo yes || echo no")

if [[ "$HAS_SUDO_BIN" == "no" ]]; then
    log "sudo not installed. Attempting to install..."
    # Try apt (Debian/Ubuntu/Proxmox), then pacman (Arch)
    INSTALL_RESULT=$(ssh_root "
        if command -v apt-get > /dev/null 2>&1; then
            apt-get update -qq > /dev/null 2>&1 && apt-get install -y -qq sudo > /dev/null 2>&1 && echo ok
        elif command -v pacman > /dev/null 2>&1; then
            pacman -Sy --noconfirm sudo > /dev/null 2>&1 && echo ok
        else
            echo fail
        fi
    " || echo "fail")

    if [[ "$INSTALL_RESULT" == *"ok"* ]]; then
        HAS_SUDO=true
        DID_INSTALL_SUDO=true
        log "sudo installed."
    else
        warn "Could not install sudo. SSH access will work but ${TARGET_USER} won't have sudo."
    fi
else
    HAS_SUDO=true
fi

if [[ "$HAS_SUDO" == true ]]; then
    SUDO_CONFIGURED=$(ssh_cmd "${LOGIN_USER}@${FQDN}" "test -f /etc/sudoers.d/${TARGET_USER} && echo yes || echo no")
    if [[ "$SUDO_CONFIGURED" == "no" ]]; then
        SUDO_GROUP="sudo"
        if [[ "${DISTRO:-}" == "arch" ]]; then
            SUDO_GROUP="wheel"
        fi

        log "Configuring passwordless sudo (group: ${SUDO_GROUP})..."
        ssh_root "usermod -aG ${SUDO_GROUP} ${TARGET_USER} && echo '${TARGET_USER} ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/${TARGET_USER} && chmod 440 /etc/sudoers.d/${TARGET_USER}"
        DID_CONFIGURE_SUDO=true
        log "Sudo configured."
    else
        log "Sudo already configured."
    fi
fi

# --- Step 8: Install the SSH key ---

TARGET_HOME=$(ssh_cmd "${LOGIN_USER}@${FQDN}" "eval echo ~${TARGET_USER}")

# Check if key is already correctly installed
KEY_INSTALLED=$(ssh_cmd "${LOGIN_USER}@${FQDN}" \
    "grep -cF '$(echo "$PUBKEY" | awk '{print $2}')' ${TARGET_HOME}/.ssh/authorized_keys 2>/dev/null || echo 0")

if [[ "$KEY_INSTALLED" -ge 1 ]]; then
    log "Key already installed for ${TARGET_USER}."
else
    # Clean up any garbage from previous failed runs
    ssh_root "mkdir -p ${TARGET_HOME}/.ssh && chmod 700 ${TARGET_HOME}/.ssh"

    # Check if authorized_keys exists and has non-key content (garbage)
    if ssh_cmd "${LOGIN_USER}@${FQDN}" "test -f ${TARGET_HOME}/.ssh/authorized_keys" 2>/dev/null; then
        VALID_KEYS=$(ssh_cmd "${LOGIN_USER}@${FQDN}" "grep -c '^ssh-' ${TARGET_HOME}/.ssh/authorized_keys 2>/dev/null || echo 0")
        TOTAL_LINES=$(ssh_cmd "${LOGIN_USER}@${FQDN}" "wc -l < ${TARGET_HOME}/.ssh/authorized_keys 2>/dev/null || echo 0")
        if [[ "$TOTAL_LINES" -gt 0 ]] && [[ "$VALID_KEYS" -eq 0 ]]; then
            warn "authorized_keys contains garbage (no valid keys). Replacing."
            ssh_root "rm -f ${TARGET_HOME}/.ssh/authorized_keys"
        fi
    fi

    log "Installing SSH key for ${TARGET_USER}..."
    ssh_root "echo '${PUBKEY}' >> ${TARGET_HOME}/.ssh/authorized_keys && chmod 600 ${TARGET_HOME}/.ssh/authorized_keys && chown -R ${TARGET_USER}:${TARGET_USER} ${TARGET_HOME}/.ssh"
    DID_INSTALL_KEY=true
    log "Key installed."
fi

# Also install key for login user so future SSH doesn't need a password
if [[ "$LOGIN_USER" != "$TARGET_USER" ]]; then
    LOGIN_HOME=$(ssh_cmd "${LOGIN_USER}@${FQDN}" "eval echo ~${LOGIN_USER}")
    LOGIN_KEY_INSTALLED=$(ssh_cmd "${LOGIN_USER}@${FQDN}" \
        "grep -cF '$(echo "$PUBKEY" | awk '{print $2}')' ${LOGIN_HOME}/.ssh/authorized_keys 2>/dev/null || echo 0")

    if [[ "$LOGIN_KEY_INSTALLED" -ge 1 ]]; then
        log "Key already installed for ${LOGIN_USER}."
    else
        log "Installing SSH key for ${LOGIN_USER} (so future SSH won't need a password)..."
        ssh_root "mkdir -p ${LOGIN_HOME}/.ssh && chmod 700 ${LOGIN_HOME}/.ssh && echo '${PUBKEY}' >> ${LOGIN_HOME}/.ssh/authorized_keys && chmod 600 ${LOGIN_HOME}/.ssh/authorized_keys"
        log "Key installed for ${LOGIN_USER}."
    fi
fi

# --- Step 9: Close master connection and test as target user ---

ssh -o ControlPath="$CONTROL_PATH" -O exit "${LOGIN_USER}@${FQDN}" 2>/dev/null || true

log "Testing SSH as ${TARGET_USER}..."

# Always test with the specific pubkey to avoid MaxAuthTries
SSH_OK=false
if ssh -o ConnectTimeout=5 -o BatchMode=yes -o IdentitiesOnly=yes -i ~/.ssh/pubkeys/${HOSTNAME}.pub "${TARGET_USER}@${FQDN}" "echo ok" > /dev/null 2>&1; then
    SSH_OK=true
    log "SSH as ${TARGET_USER} works (direct key)."
else
    # Try with SSH config alias if one exists
    if grep -q "^Host ${HOSTNAME}$" ~/.ssh/config 2>/dev/null; then
        if ssh -o ConnectTimeout=5 -o BatchMode=yes "${HOSTNAME}" "echo ok" > /dev/null 2>&1; then
            SSH_OK=true
            log "SSH as ${TARGET_USER} works (via config alias)."
        fi
    fi

    # Add config entry if still failing
    if [[ "$SSH_OK" == false ]]; then
        warn "Direct key test failed. Adding SSH config entry..."
        if ! grep -q "^Host ${HOSTNAME}$" ~/.ssh/config 2>/dev/null; then
            cat >> ~/.ssh/config <<EOF

Host ${HOSTNAME}
    HostName ${FQDN}
    User ${TARGET_USER}
    IdentityFile ~/.ssh/pubkeys/${HOSTNAME}.pub
    IdentitiesOnly yes
EOF
            DID_ADD_SSH_CONFIG=true
            log "Added SSH config entry for ${HOSTNAME}."
        fi

        if ssh -o ConnectTimeout=5 -o BatchMode=yes "${HOSTNAME}" "echo ok" > /dev/null 2>&1; then
            SSH_OK=true
            log "SSH via config alias works."
        fi
    fi
fi

if [[ "$SSH_OK" == false ]]; then
    err "Cannot connect as ${TARGET_USER}."
    echo "Debug: ssh -v -o IdentitiesOnly=yes -i ~/.ssh/pubkeys/${HOSTNAME}.pub ${TARGET_USER}@${FQDN}"
    exit 1
fi

# --- Step 10: Final verification ---

VERIFY_CMD="whoami"
if [[ "$HAS_SUDO" == true ]]; then
    VERIFY_CMD="whoami && sudo whoami"
fi

RESULT=$(ssh -o ConnectTimeout=5 -o BatchMode=yes -o IdentitiesOnly=yes -i ~/.ssh/pubkeys/${HOSTNAME}.pub "${TARGET_USER}@${FQDN}" "$VERIFY_CMD" 2>/dev/null || \
         ssh -o ConnectTimeout=5 -o BatchMode=yes "${HOSTNAME}" "$VERIFY_CMD" 2>/dev/null || \
         echo "")

if [[ -z "$RESULT" ]] || [[ "$RESULT" != *"${TARGET_USER}"* ]]; then
    warn "Final verification returned unexpected output: ${RESULT:-<empty>}"
    warn "SSH connection works but something may be off. Check manually."
fi

# --- Summary ---

echo ""
echo "=== Done ==="
echo "Host:   ${FQDN} (${IP})"
echo "User:   ${TARGET_USER}"
echo "Key:    ${HOSTNAME} SSH Key"
echo "Pubkey: ~/.ssh/pubkeys/${HOSTNAME}.pub"
echo "OS:     ${DETECTED_OS} (${DISTRO:-n/a})"
if [[ "$HAS_SUDO" == true ]]; then
    echo "Sudo:   yes (NOPASSWD)"
else
    echo "Sudo:   no (could not install)"
fi
echo "SSH:    ssh ${TARGET_USER}@${FQDN}"
if [[ "$DID_ADD_SSH_CONFIG" == true ]]; then
    echo "Config: ~/.ssh/config entry added (Host ${HOSTNAME})"
fi
echo ""

# What we did
ACTIONS=()
[[ "$DID_CREATE_USER" == true ]] && ACTIONS+=("created user ${TARGET_USER}")
[[ "$DID_INSTALL_SUDO" == true ]] && ACTIONS+=("installed sudo")
[[ "$DID_CONFIGURE_SUDO" == true ]] && ACTIONS+=("configured passwordless sudo")
[[ "$DID_INSTALL_KEY" == true ]] && ACTIONS+=("installed SSH key")
[[ "$DID_ADD_SSH_CONFIG" == true ]] && ACTIONS+=("added SSH config entry")

if [[ ${#ACTIONS[@]} -gt 0 ]]; then
    echo "Actions taken:"
    for action in "${ACTIONS[@]}"; do
        echo "  - ${action}"
    done
else
    echo "No changes needed — everything was already set up."
fi

echo ""
echo "Next steps:"
echo "  - Update Proton Pass PAT Setup doc (PAT Storage table + SSH Keys list)"
echo "  - (Optional) Seal a TPM PAT on ${HOSTNAME} if it needs pass-cli"
