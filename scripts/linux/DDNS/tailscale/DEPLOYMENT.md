# Tailscale DNS Updater - Deployment Instructions

## Prerequisites
1. Ubuntu Linux machine
2. Tailscale installed and running
3. Cloudflare account with DNS zone
4. Domain configured in Cloudflare (elikesbikes.com)

## Step 1: Get Cloudflare Credentials

### Global API Key:
1. Go to: https://dash.cloudflare.com/profile/api-tokens
2. Under "API Keys", find "Global API Key"
3. Click "View" and copy the key

### Zone ID:
1. In Cloudflare dashboard, select your domain
2. Right sidebar, under "API", find "Zone ID"
3. Copy the Zone ID

### Record ID:
1. Run: `./get-cloudflare-ids.sh` (if available)
2. Or use API to list records and find the ID for ranger0.home.elikesbikes.com

## Step 2: Install Script

```bash
# Create script directory
mkdir -p /home/ecloaiza/scripts/linux/DDNS

# Copy script to directory
cp tailscale-ddns-updater.sh /home/ecloaiza/scripts/linux/DDNS/

# Make executable
chmod +x /home/ecloaiza/scripts/linux/DDNS/tailscale-ddns-updater.sh


## 3. Configure
# Create config file
cat > /home/ecloaiza/.env.tailscale-ddns << 'EOF'
CLOUDFLARE_EMAIL="your_email@example.com"
CLOUDFLARE_API_KEY="your_global_api_key"
CLOUDFLARE_ZONE_ID="your_zone_id"
CLOUDFLARE_RECORD_ID="your_record_id"
EOF

chmod 600 /home/ecloaiza/.env.tailscale-ddns


## 4. Setup Logs
sudo mkdir -p /var/log/tailscale-ddns-updater
sudo chown ecloaiza:ecloaiza /var/log/tailscale-ddns-updater

## 4. Setup Logs
sudo chown ecloaiza:ecloaiza /var/log/tailscale-ddns-updater
/home/ecloaiza/scripts/linux/DDNS/tailscale-ddns-updater.sh
tail -f /var/log/tailscale-ddns-updater/tailscale-ddns-updater.log

## 5. Test

/home/ecloaiza/scripts/linux/DDNS/tailscale-ddns-updater.sh
tail -f /var/log/tailscale-ddns-updater/tailscale-ddns-updater.log

## 6. Schedule (Optional)
crontab -e
# Add: 0 9,21 * * * /home/ecloaiza/scripts/linux/DDNS/tailscale-ddns-updater.sh


## 7. Verify
dig +short ranger0.home.elikesbikes.com
tailscale ip -4