#!/bin/bash

# ============================================
# Tailscale Cloudflare DNS Updater
# Version: 1.0.0
# Author: Tailscale DDNS Script
# ============================================

# Configuration
SCRIPT_NAME="tailscale-ddns-updater"
SCRIPT_VERSION="1.0.0"
LOG_DIR="/var/log/${SCRIPT_NAME}"
LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}.log"
CONFIG_DIR="/home/ecloaiza"
ENV_FILE="${CONFIG_DIR}/.env.tailscale-ddns"
STATE_FILE="${CONFIG_DIR}/.tailscale-ddns.state"
LOCK_FILE="/tmp/${SCRIPT_NAME}.lock"

# Cloudflare DNS Configuration
DNS_RECORD_NAME="ranger0.home"
DNS_RECORD_TYPE="A"

# Tailscale interface (default, but can be overridden)
TAILSCALE_INTERFACE="tailscale0"

# ============================================
# Logging Functions
# ============================================

setup_logging() {
    # Create log directory if it doesn't exist
    if [ ! -d "${LOG_DIR}" ]; then
        mkdir -p "${LOG_DIR}"
        chmod 755 "${LOG_DIR}"
    fi
    
    # Create log file if it doesn't exist
    if [ ! -f "${LOG_FILE}" ]; then
        touch "${LOG_FILE}"
        chmod 644 "${LOG_FILE}"
    fi
}

log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log_message "INFO" "$1"
}

log_error() {
    log_message "ERROR" "$1"
}

log_debug() {
    log_message "DEBUG" "$1"
}

# ============================================
# Configuration Functions
# ============================================

load_configuration() {
    if [ ! -f "${ENV_FILE}" ]; then
        log_error "Configuration file not found: ${ENV_FILE}"
        log_error "Please create the configuration file with the following variables:"
        log_error "  CLOUDFLARE_API_TOKEN=your_api_token_here"
        log_error "  CLOUDFLARE_ZONE_ID=your_zone_id_here"
        log_error "  CLOUDFLARE_RECORD_ID=your_record_id_here"
        exit 1
    fi
    
    # Load environment variables
    source "${ENV_FILE}"
    
    # Validate required variables
    local required_vars=("CLOUDFLARE_API_TOKEN" "CLOUDFLARE_ZONE_ID" "CLOUDFLARE_RECORD_ID")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("${var}")
        fi
    done
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        log_error "Missing required configuration variables: ${missing_vars[*]}"
        exit 1
    fi
    
    log_info "Configuration loaded successfully"
}

# ============================================
# Locking Mechanism
# ============================================

acquire_lock() {
    if [ -f "${LOCK_FILE}" ]; then
        local pid=$(cat "${LOCK_FILE}")
        if kill -0 "${pid}" 2>/dev/null; then
            log_error "Script is already running (PID: ${pid})"
            exit 1
        else
            log_warning "Stale lock file found, removing..."
            rm -f "${LOCK_FILE}"
        fi
    fi
    
    echo $$ > "${LOCK_FILE}"
    log_debug "Lock acquired"
}

release_lock() {
    rm -f "${LOCK_FILE}"
    log_debug "Lock released"
}

# ============================================
# IP Address Functions
# ============================================

get_tailscale_ip() {
    local ip_address
    
    # Try to get IP from tailscale interface
    ip_address=$(ip -4 addr show ${TAILSCALE_INTERFACE} 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    
    if [ -z "${ip_address}" ]; then
        # Fallback to tailscale CLI
        ip_address=$(tailscale ip -4 2>/dev/null | head -n1)
    fi
    
    if [ -z "${ip_address}" ]; then
        log_error "Could not determine Tailscale IP address"
        return 1
    fi
    
    echo "${ip_address}"
    log_info "Current Tailscale IP: ${ip_address}"
    return 0
}

get_current_dns_ip() {
    local dns_ip
    
    # Use dig to query Cloudflare DNS directly
    dns_ip=$(dig +short ${DNS_RECORD_NAME} @1.1.1.1 2>/dev/null | head -n1)
    
    if [ -z "${dns_ip}" ]; then
        log_warning "Could not resolve DNS record for ${DNS_RECORD_NAME}"
        echo ""
        return 1
    fi
    
    log_info "Current DNS IP: ${dns_ip}"
    echo "${dns_ip}"
    return 0
}

# ============================================
# Cloudflare API Functions
# ============================================

get_cloudflare_record() {
    local response
    local current_ip
    
    response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${CLOUDFLARE_RECORD_ID}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json")
    
    if echo "${response}" | grep -q '"success":true'; then
        current_ip=$(echo "${response}" | grep -o '"content":"[^"]*"' | cut -d'"' -f4)
        log_info "Cloudflare record IP: ${current_ip}"
        echo "${current_ip}"
        return 0
    else
        log_error "Failed to fetch Cloudflare DNS record"
        log_debug "API Response: ${response}"
        return 1
    fi
}

update_cloudflare_dns() {
    local new_ip="$1"
    local response
    
    log_info "Updating DNS record to ${new_ip}"
    
    response=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${CLOUDFLARE_RECORD_ID}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"${DNS_RECORD_TYPE}\",\"name\":\"${DNS_RECORD_NAME}\",\"content\":\"${new_ip}\",\"ttl\":120,\"proxied\":false}")
    
    if echo "${response}" | grep -q '"success":true'; then
        log_info "DNS record updated successfully"
        
        # Save state
        echo "LAST_UPDATE=$(date +%s)" > "${STATE_FILE}"
        echo "LAST_IP=${new_ip}" >> "${STATE_FILE}"
        
        return 0
    else
        log_error "Failed to update DNS record"
        log_debug "API Response: ${response}"
        return 1
    fi
}

# ============================================
# State Management
# ============================================

load_state() {
    if [ -f "${STATE_FILE}" ]; then
        source "${STATE_FILE}"
        log_debug "State loaded: LAST_IP=${LAST_IP:-Not Set}, LAST_UPDATE=${LAST_UPDATE:-0}"
    else
        log_debug "No previous state found"
    fi
}

# ============================================
# Main Execution
# ============================================

main() {
    log_info "========================================="
    log_info "Tailscale DNS Updater v${SCRIPT_VERSION}"
    log_info "Start time: $(date)"
    log_info "========================================="
    
    # Setup
    setup_logging
    acquire_lock
    
    # Load configuration
    load_configuration
    
    # Load previous state
    load_state
    
    # Get current IP addresses
    local tailscale_ip
    local dns_ip
    
    tailscale_ip=$(get_tailscale_ip)
    if [ $? -ne 0 ]; then
        log_error "Failed to get Tailscale IP"
        release_lock
        exit 1
    fi
    
    dns_ip=$(get_cloudflare_record)
    if [ $? -ne 0 ]; then
        log_error "Failed to get Cloudflare DNS record"
        release_lock
        exit 1
    fi
    
    # Compare IP addresses
    if [ "${tailscale_ip}" = "${dns_ip}" ]; then
        log_info "IP addresses match (${tailscale_ip}). No update needed."
    else
        log_info "IP addresses differ: Tailscale=${tailscale_ip}, DNS=${dns_ip}"
        log_info "Updating DNS record..."
        
        if update_cloudflare_dns "${tailscale_ip}"; then
            log_info "DNS update completed successfully"
        else
            log_error "DNS update failed"
            release_lock
            exit 1
        fi
    fi
    
    # Cleanup
    release_lock
    log_info "Script completed successfully"
    log_info "========================================="
}

# Error handling
handle_error() {
    log_error "Script terminated with error"
    log_error "Error occurred at line: $1"
    release_lock
    exit 1
}

# Set up error trap
trap 'handle_error $LINENO' ERR

# Execute main function
main "$@"