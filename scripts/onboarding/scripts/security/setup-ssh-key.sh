#!/bin/bash
set -uo pipefail

# Setup SSH key access on a new host using Proton Pass SSH agent.
# Supports: Ubuntu, Debian, Proxmox, Arch, Windows (OpenSSH).
# Works with: LXC, VM, bare metal, Proxmox hosts.
#
# Permutations handled:
#   - Login as root (direct privilege) or non-root (uses sudo)
#   - Login user same as target user (just install key, skip user/sudo setup)
#   - Password auth or key auth on initial connect
#   - sudo installed or missing (installs it if login user has privilege)
#   - Target user exists or needs creation
#   - Debian/Ubuntu (sudo group) vs Arch (wheel group)
#   - Windows admin (administrators_authorized_keys) vs non-admin (.ssh/)
#   - MaxAuthTries workaround (pubkey file + SSH config entry)
#   - Garbage in authorized_keys from previous failed runs

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
  $(basename "$0") endurance                            # Proxmox LXC, root key injected
  $(basename "$0") --password endurance                  # Fresh machine, need password
  $(basename "$0") --password --user emmanuel kipp       # Ubuntu Desktop, SSH as install user
  $(basename "$0") --windows --password nvr-prod-1       # Windows host
  $(basename "$0") --ip 192.168.5.50 newbox              # Use IP, key name is 'newbox SSH Key'
  $(basename "$0") --password --user ecloaiza mydesktop  # Login user IS target user
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

# --- SSH multiplexing — single password prompt reused for all commands ---
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

# Run a command with root privilege on the remote host.
# - login user is root: run directly
# - login user has sudo: prefix with sudo
# - login user has no privilege: fail with guidance
run_privileged() {
    local cmd="$1"
    if [[ "$LOGIN_USER" == "root" ]]; then
        ssh_cmd "${LOGIN_USER}@${FQDN}" "$cmd"
    elif [[ "$CAN_SUDO" == true ]]; then
        ssh_cmd "${LOGIN_USER}@${FQDN}" "sudo bash -c '$cmd'"
    else
        err "Need root privileges to run: $cmd"
        err "Login user ${LOGIN_USER} is not root and doesn't have sudo."
        return 1
    fi
}

# Track what we did for the summary
DID_CREATE_USER=false
DID_INSTALL_SUDO=false
DID_CONFIGURE_SUDO=false
DID_INSTALL_KEY=false
DID_INSTALL_LOGIN_KEY=false
DID_ADD_SSH_CONFIG=false
HAS_SUDO=false
CAN_SUDO=false
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

PUBKEY_FINGERPRINT=$(echo "$PUBKEY" | awk '{print $2}')
log "Found public key: ${PUBKEY:0:50}..."

# Save pubkey to file now — needed for testing later (avoids MaxAuthTries)
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
# Step 5: Detect OS and privilege level
# ============================================================

HOST_TYPE=""  # proxmox, truenas-scale, truenas-core, lxc, macos, windows, linux
SUDO_GROUP_NAME="sudo"

if [[ "$IS_WINDOWS" == true ]]; then
    DETECTED_OS="windows"
    HOST_TYPE="windows"
    log "Target OS: Windows (manual flag)"
else
    DETECTED_OS=$(ssh_cmd "${LOGIN_USER}@${FQDN}" "uname -s 2>/dev/null || echo unknown" | tr '[:upper:]' '[:lower:]')
    if [[ "$DETECTED_OS" == *"mingw"* ]] || [[ "$DETECTED_OS" == *"msys"* ]] || [[ "$DETECTED_OS" == *"cygwin"* ]]; then
        DETECTED_OS="windows"
        HOST_TYPE="windows"
    fi

    if [[ "$DETECTED_OS" == "darwin" ]]; then
        HOST_TYPE="macos"
        DISTRO="macos"
        SUDO_GROUP_NAME="admin"
        MACOS_VERSION=$(ssh_cmd "${LOGIN_USER}@${FQDN}" "sw_vers -productVersion 2>/dev/null" || true)
        log "Target OS: macOS ${MACOS_VERSION:-unknown}"

    elif [[ "$DETECTED_OS" == "freebsd" ]]; then
        # TrueNAS CORE is FreeBSD-based
        IS_TRUENAS=$(ssh_cmd "${LOGIN_USER}@${FQDN}" "test -f /etc/version && grep -qi truenas /etc/version 2>/dev/null && echo yes || echo no")
        if [[ "$IS_TRUENAS" == "yes" ]]; then
            HOST_TYPE="truenas-core"
            DISTRO="truenas-core"
            log "Target OS: TrueNAS CORE (FreeBSD)"
            warn "TrueNAS CORE users should be created through the web UI."
            warn "CLI-created users may be overwritten on system updates."
        else
            HOST_TYPE="freebsd"
            DISTRO="freebsd"
            log "Target OS: FreeBSD"
        fi
        SUDO_GROUP_NAME="wheel"

    elif [[ "$DETECTED_OS" == "linux" ]]; then
        DISTRO=$(ssh_cmd "${LOGIN_USER}@${FQDN}" "grep -oP '^ID=\K.*' /etc/os-release 2>/dev/null | tr -d '\"'" || true)

        # Detect host type more specifically
        IS_PROXMOX=$(ssh_cmd "${LOGIN_USER}@${FQDN}" "test -d /etc/pve && echo yes || echo no")
        IS_TRUENAS_SCALE=$(ssh_cmd "${LOGIN_USER}@${FQDN}" "test -f /etc/version && grep -qi truenas /etc/version 2>/dev/null && echo yes || echo no")
        IS_LXC=$(ssh_cmd "${LOGIN_USER}@${FQDN}" "systemd-detect-virt 2>/dev/null || echo unknown")

        if [[ "$IS_PROXMOX" == "yes" ]]; then
            HOST_TYPE="proxmox"
            log "Target OS: Proxmox VE (${DISTRO:-debian})"
        elif [[ "$IS_TRUENAS_SCALE" == "yes" ]]; then
            HOST_TYPE="truenas-scale"
            log "Target OS: TrueNAS SCALE (${DISTRO:-debian})"
            warn "TrueNAS SCALE users should be created through the web UI."
            warn "CLI-created users may be overwritten on system updates."
        elif [[ "$IS_LXC" == "lxc" ]]; then
            HOST_TYPE="lxc"
            log "Target OS: LXC container (${DISTRO:-unknown})"
        else
            HOST_TYPE="linux"
            log "Target OS: Linux (${DISTRO:-unknown distro})"
        fi

        # Set sudo group based on distro
        if [[ "${DISTRO:-}" == "arch" ]]; then
            SUDO_GROUP_NAME="wheel"
        fi
    else
        log "Target OS: ${DETECTED_OS}"
    fi
fi

# Determine privilege level of login user
if [[ "$LOGIN_USER" == "root" ]]; then
    CAN_SUDO=false  # don't need sudo, we ARE root
    log "Login user is root — full privilege."
elif [[ "$DETECTED_OS" != "windows" ]]; then
    # Check if login user can sudo without a password
    SUDO_CHECK=$(ssh_cmd "${LOGIN_USER}@${FQDN}" "sudo -n true 2>/dev/null && echo yes || echo no")
    if [[ "$SUDO_CHECK" == "yes" ]]; then
        CAN_SUDO=true
        log "Login user ${LOGIN_USER} has passwordless sudo."
    else
        # Try with password (the multiplexed session may pass it through)
        SUDO_CHECK_PW=$(ssh_cmd "${LOGIN_USER}@${FQDN}" "sudo true 2>/dev/null && echo yes || echo no")
        if [[ "$SUDO_CHECK_PW" == "yes" ]]; then
            CAN_SUDO=true
            log "Login user ${LOGIN_USER} has sudo (password was accepted)."
        else
            CAN_SUDO=false
            if [[ "$LOGIN_USER" == "$TARGET_USER" ]]; then
                log "Login user ${LOGIN_USER} has no sudo — will install key for own account only."
            else
                warn "Login user ${LOGIN_USER} has no sudo. Can install key but cannot create users or configure sudo."
            fi
        fi
    fi
fi

# ============================================================
# Windows path
# ============================================================

if [[ "$DETECTED_OS" == "windows" ]]; then
    log "Setting up SSH key on Windows host..."

    HAS_HOME=$(ssh_cmd "${LOGIN_USER}@${FQDN}" "powershell -Command \"Test-Path C:\\Users\\${TARGET_USER}\"" 2>/dev/null | tr -d '\r' || echo "False")
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
        "powershell -Command \"if (Test-Path '${KEY_FILE}') { (Get-Content '${KEY_FILE}' | Select-String -SimpleMatch '${PUBKEY_FINGERPRINT}' -Quiet) } else { 'False' }\"" 2>/dev/null || echo "False")

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

HAS_PRIVILEGE=false
if [[ "$LOGIN_USER" == "root" ]] || [[ "$CAN_SUDO" == true ]]; then
    HAS_PRIVILEGE=true
fi

# --- Step 6: Check / create user ---

USER_EXISTS=$(ssh_cmd "${LOGIN_USER}@${FQDN}" "id ${TARGET_USER} > /dev/null 2>&1 && echo yes || echo no")

if [[ "$USER_EXISTS" == "no" ]]; then
    if [[ "$HAS_PRIVILEGE" == true ]]; then
        log "User ${TARGET_USER} does not exist. Creating..."

        if [[ "$HOST_TYPE" == "truenas-core" ]] || [[ "$HOST_TYPE" == "truenas-scale" ]]; then
            warn "Creating user via CLI on TrueNAS. This may be overwritten by system updates."
            warn "Consider creating the user through the TrueNAS web UI instead."
        fi

        case "$HOST_TYPE" in
            macos)
                # macOS uses sysadminctl, not useradd
                # Create as admin user so they get sudo via admin group
                run_privileged "sysadminctl -addUser ${TARGET_USER} -password '' -admin"
                ;;
            truenas-core|freebsd)
                # FreeBSD uses pw, not useradd
                run_privileged "pw useradd ${TARGET_USER} -m -s /bin/sh -G ${SUDO_GROUP_NAME}"
                ;;
            *)
                # Linux: Ubuntu, Debian, Arch, Proxmox, LXC, TrueNAS SCALE
                run_privileged "useradd -m -s /bin/bash ${TARGET_USER}"
                ;;
        esac
        DID_CREATE_USER=true
        log "User ${TARGET_USER} created."
    else
        err "User ${TARGET_USER} does not exist and login user ${LOGIN_USER} has no privilege to create it."
        echo "Either:"
        echo "  - Run this script with --user root"
        case "$HOST_TYPE" in
            macos)
                echo "  - Create the user in System Settings → Users & Groups"
                ;;
            truenas-core|truenas-scale)
                echo "  - Create the user in the TrueNAS web UI → Accounts → Users"
                ;;
            windows)
                echo "  - Create the user: net user ${TARGET_USER} <password> /add"
                ;;
            *)
                echo "  - Create the user manually: useradd -m -s /bin/bash ${TARGET_USER}"
                ;;
        esac
        exit 1
    fi
else
    log "User ${TARGET_USER} already exists."
fi

# --- Step 7: Install sudo if missing, configure if needed ---
# Skip if login user has no privilege (can't install or configure sudo)
# Skip if login user IS target user and already has sudo

if [[ "$HAS_PRIVILEGE" == true ]]; then
    HAS_SUDO_BIN=$(ssh_cmd "${LOGIN_USER}@${FQDN}" "command -v sudo > /dev/null 2>&1 && echo yes || echo no")

    if [[ "$HAS_SUDO_BIN" == "no" ]]; then
        if [[ "$HOST_TYPE" == "macos" ]]; then
            # macOS always has sudo — if we're here something is very wrong
            warn "sudo not found on macOS — this is unexpected. Skipping install."
            INSTALL_RESULT="fail"
        else
            log "sudo not installed. Attempting to install..."
            INSTALL_RESULT=$(run_privileged "
                if command -v apt-get > /dev/null 2>&1; then
                    apt-get update -qq > /dev/null 2>&1 && apt-get install -y -qq sudo > /dev/null 2>&1 && echo ok
                elif command -v pacman > /dev/null 2>&1; then
                    pacman -Sy --noconfirm sudo > /dev/null 2>&1 && echo ok
                elif command -v pkg > /dev/null 2>&1; then
                    pkg install -y sudo > /dev/null 2>&1 && echo ok
                else
                    echo fail
                fi
            " || echo "fail")
        fi

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
        if [[ "$HOST_TYPE" == "macos" ]]; then
            # macOS: sudo is granted via admin group membership, not sudoers.d
            IN_ADMIN=$(ssh_cmd "${LOGIN_USER}@${FQDN}" "dscl . -read /Groups/admin GroupMembership 2>/dev/null | grep -qw ${TARGET_USER} && echo yes || echo no")
            if [[ "$IN_ADMIN" == "yes" ]]; then
                log "User ${TARGET_USER} is in admin group (has sudo)."
            else
                log "Adding ${TARGET_USER} to admin group for sudo..."
                run_privileged "dseditgroup -o edit -a ${TARGET_USER} -t user admin"
                DID_CONFIGURE_SUDO=true
                log "Sudo configured (admin group)."
            fi
        else
            # Linux / FreeBSD: use sudoers.d
            SUDO_CONFIGURED=$(ssh_cmd "${LOGIN_USER}@${FQDN}" "test -f /etc/sudoers.d/${TARGET_USER} && echo yes || echo no")
            if [[ "$SUDO_CONFIGURED" == "no" ]]; then
                log "Configuring passwordless sudo (group: ${SUDO_GROUP_NAME})..."
                if [[ "$HOST_TYPE" == "truenas-core" ]] || [[ "$HOST_TYPE" == "freebsd" ]]; then
                    run_privileged "pw groupmod ${SUDO_GROUP_NAME} -m ${TARGET_USER}"
                else
                    run_privileged "usermod -aG ${SUDO_GROUP_NAME} ${TARGET_USER}"
                fi
                run_privileged "echo '${TARGET_USER} ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/${TARGET_USER} && chmod 440 /etc/sudoers.d/${TARGET_USER}"
                DID_CONFIGURE_SUDO=true
                log "Sudo configured."
            else
                log "Sudo already configured."
            fi
        fi
    fi
else
    # No privilege — check if sudo exists and target user has it
    HAS_SUDO_BIN=$(ssh_cmd "${LOGIN_USER}@${FQDN}" "command -v sudo > /dev/null 2>&1 && echo yes || echo no")
    if [[ "$HAS_SUDO_BIN" == "yes" ]]; then
        HAS_SUDO=true
        warn "No privilege to configure sudo — assuming existing setup is fine."
    else
        warn "No privilege to install or configure sudo. ${TARGET_USER} will have SSH access only."
    fi
fi

# --- Step 8: Install the SSH key ---

TARGET_HOME=$(ssh_cmd "${LOGIN_USER}@${FQDN}" "eval echo ~${TARGET_USER}")

# Check if key is already correctly installed
KEY_INSTALLED=$(ssh_cmd "${LOGIN_USER}@${FQDN}" \
    "grep -cF '${PUBKEY_FINGERPRINT}' ${TARGET_HOME}/.ssh/authorized_keys 2>/dev/null || echo 0")

if [[ "$KEY_INSTALLED" -ge 1 ]]; then
    log "Key already installed for ${TARGET_USER}."
else
    # Determine if we need privilege to write to target user's home
    if [[ "$LOGIN_USER" == "$TARGET_USER" ]]; then
        # Writing to our own home — no privilege needed
        WRITE_CMD="ssh_cmd"
    elif [[ "$HAS_PRIVILEGE" == true ]]; then
        WRITE_CMD="run_privileged"
    else
        err "Cannot install key for ${TARGET_USER} — login user ${LOGIN_USER} has no privilege to write to ${TARGET_HOME}/.ssh/"
        echo "Either:"
        echo "  - Run with --user root or a user with sudo"
        echo "  - Run with --user ${TARGET_USER} if that user has password auth"
        exit 1
    fi

    # Clean up garbage from previous failed runs
    if ssh_cmd "${LOGIN_USER}@${FQDN}" "test -f ${TARGET_HOME}/.ssh/authorized_keys" 2>/dev/null; then
        VALID_KEYS=$(ssh_cmd "${LOGIN_USER}@${FQDN}" "grep -c '^ssh-' ${TARGET_HOME}/.ssh/authorized_keys 2>/dev/null || echo 0")
        TOTAL_LINES=$(ssh_cmd "${LOGIN_USER}@${FQDN}" "wc -l < ${TARGET_HOME}/.ssh/authorized_keys 2>/dev/null || echo 0")
        TOTAL_LINES=$(echo "$TOTAL_LINES" | tr -d '[:space:]')
        if [[ "$TOTAL_LINES" -gt 0 ]] && [[ "$VALID_KEYS" -eq 0 ]]; then
            warn "authorized_keys contains garbage (no valid keys). Cleaning up."
            $WRITE_CMD "rm -f ${TARGET_HOME}/.ssh/authorized_keys"
        fi
    fi

    log "Installing SSH key for ${TARGET_USER}..."
    if [[ "$LOGIN_USER" == "$TARGET_USER" ]]; then
        ssh_cmd "${LOGIN_USER}@${FQDN}" "mkdir -p ${TARGET_HOME}/.ssh && chmod 700 ${TARGET_HOME}/.ssh && echo '${PUBKEY}' >> ${TARGET_HOME}/.ssh/authorized_keys && chmod 600 ${TARGET_HOME}/.ssh/authorized_keys"
    else
        run_privileged "mkdir -p ${TARGET_HOME}/.ssh && chmod 700 ${TARGET_HOME}/.ssh && echo '${PUBKEY}' >> ${TARGET_HOME}/.ssh/authorized_keys && chmod 600 ${TARGET_HOME}/.ssh/authorized_keys && chown -R ${TARGET_USER}:${TARGET_USER} ${TARGET_HOME}/.ssh"
    fi
    DID_INSTALL_KEY=true
    log "Key installed."
fi

# Also install key for login user so future SSH won't need a password
if [[ "$LOGIN_USER" != "$TARGET_USER" ]]; then
    LOGIN_HOME=$(ssh_cmd "${LOGIN_USER}@${FQDN}" "eval echo ~${LOGIN_USER}")
    LOGIN_KEY_INSTALLED=$(ssh_cmd "${LOGIN_USER}@${FQDN}" \
        "grep -cF '${PUBKEY_FINGERPRINT}' ${LOGIN_HOME}/.ssh/authorized_keys 2>/dev/null || echo 0")

    if [[ "$LOGIN_KEY_INSTALLED" -ge 1 ]]; then
        log "Key already installed for ${LOGIN_USER}."
    else
        log "Installing SSH key for ${LOGIN_USER} (so future SSH won't need a password)..."
        if [[ "$LOGIN_USER" == "root" ]]; then
            ssh_cmd "${LOGIN_USER}@${FQDN}" "mkdir -p ${LOGIN_HOME}/.ssh && chmod 700 ${LOGIN_HOME}/.ssh && echo '${PUBKEY}' >> ${LOGIN_HOME}/.ssh/authorized_keys && chmod 600 ${LOGIN_HOME}/.ssh/authorized_keys"
        else
            # Non-root login user can write to their own home
            ssh_cmd "${LOGIN_USER}@${FQDN}" "mkdir -p ${LOGIN_HOME}/.ssh && chmod 700 ${LOGIN_HOME}/.ssh && echo '${PUBKEY}' >> ${LOGIN_HOME}/.ssh/authorized_keys && chmod 600 ${LOGIN_HOME}/.ssh/authorized_keys"
        fi
        DID_INSTALL_LOGIN_KEY=true
        log "Key installed for ${LOGIN_USER}."
    fi
fi

# ============================================================
# Step 9: Close master connection and test as target user
# ============================================================

ssh -o ControlPath="$CONTROL_PATH" -O exit "${LOGIN_USER}@${FQDN}" 2>/dev/null || true

log "Testing SSH as ${TARGET_USER}..."

SSH_OK=false

# Always test with the specific pubkey to avoid MaxAuthTries
if ssh -o ConnectTimeout=5 -o BatchMode=yes -o IdentitiesOnly=yes -i ~/.ssh/pubkeys/${HOSTNAME}.pub "${TARGET_USER}@${FQDN}" "echo ok" > /dev/null 2>&1; then
    SSH_OK=true
    log "SSH as ${TARGET_USER} works (direct key)."
else
    # Try existing config alias
    if grep -q "^Host ${HOSTNAME}$" ~/.ssh/config 2>/dev/null; then
        if ssh -o ConnectTimeout=5 -o BatchMode=yes "${HOSTNAME}" "echo ok" > /dev/null 2>&1; then
            SSH_OK=true
            log "SSH as ${TARGET_USER} works (via existing config alias)."
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
    err "Cannot connect as ${TARGET_USER} after setup."
    echo "Debug: ssh -v -o IdentitiesOnly=yes -i ~/.ssh/pubkeys/${HOSTNAME}.pub ${TARGET_USER}@${FQDN}"
    exit 1
fi

# ============================================================
# Step 10: Final verification
# ============================================================

VERIFY_CMD="whoami"
if [[ "$HAS_SUDO" == true ]]; then
    VERIFY_CMD="whoami && sudo -n whoami 2>/dev/null || echo '(sudo not available or needs password)'"
fi

RESULT=$(ssh -o ConnectTimeout=5 -o BatchMode=yes -o IdentitiesOnly=yes -i ~/.ssh/pubkeys/${HOSTNAME}.pub "${TARGET_USER}@${FQDN}" "$VERIFY_CMD" 2>/dev/null || \
         ssh -o ConnectTimeout=5 -o BatchMode=yes "${HOSTNAME}" "$VERIFY_CMD" 2>/dev/null || \
         echo "")

if [[ -z "$RESULT" ]] || [[ "$RESULT" != *"${TARGET_USER}"* ]]; then
    warn "Verification returned unexpected output: ${RESULT:-<empty>}"
    warn "SSH works but something may be off — check manually."
fi

# ============================================================
# Summary
# ============================================================

echo ""
echo "=== Done ==="
echo "Host:   ${FQDN} (${IP})"
echo "User:   ${TARGET_USER}"
echo "Key:    ${HOSTNAME} SSH Key"
echo "Pubkey: ~/.ssh/pubkeys/${HOSTNAME}.pub"
echo "OS:     ${DETECTED_OS} (${HOST_TYPE}${DISTRO:+, ${DISTRO}})"
if [[ "$HAS_SUDO" == true ]]; then
    echo "Sudo:   yes (NOPASSWD)"
elif [[ "$HAS_PRIVILEGE" == false ]]; then
    echo "Sudo:   unknown (no privilege to check/configure)"
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
[[ "$DID_INSTALL_KEY" == true ]] && ACTIONS+=("installed SSH key for ${TARGET_USER}")
[[ "$DID_INSTALL_LOGIN_KEY" == true ]] && ACTIONS+=("installed SSH key for ${LOGIN_USER}")
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
