# Tailscale DNS Updater - Overview

## Purpose
This script automatically updates a Cloudflare DNS record with your dynamic Tailscale IP address. When your Tailscale tunnel IP changes, the script detects the change and updates the DNS record via Cloudflare's API.

## Use Case
- You have a Tailscale VPN tunnel with a dynamic IP
- You want to access your device via a domain name (e.g., ranger0.home.elikesbikes.com)
- The Tailscale IP can change over time
- You need the DNS record to stay synchronized with the current IP

## How It Works
1. **Check Current Tailscale IP**: Reads the IP from the Tailscale interface (tailscale0)
2. **Check Current DNS Record**: Queries Cloudflare API for the current DNS IP
3. **Compare IPs**: If they differ, proceed to update
4. **Update DNS**: Use Cloudflare API to update the A record
5. **Log Everything**: All actions are logged for troubleshooting

## Key Features
- Automatic IP detection from Tailscale
- Cloudflare API integration
- Comprehensive logging system
- Locking mechanism to prevent concurrent runs
- State tracking (last update time, last IP)
- Error handling and validation

## Components
- **Main Script**: `tailscale-ddns-updater.sh` - Core logic
- **Configuration**: `.env.tailscale-ddns` - API credentials and settings
- **Logs**: `/var/log/tailscale-ddns-updater/` - Log files
- **State File**: `.tailscale-ddns.state` - Track last update

## Authentication
Uses Cloudflare Global API Key with:
- Email authentication
- API Key with DNS edit permissions

## Record Managed
- **Type**: A record
- **Name**: ranger0.home.elikesbikes.com
- **TTL**: 120 seconds (can be adjusted)
- **Proxy**: Disabled (DNS only)