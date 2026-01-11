
## **File 3: CHANGELOG.md**

```markdown
# Tailscale DNS Updater - Changelog

All notable changes to this project will be documented in this file.

## [1.1.0] - 2026-01-04

### Changed
- **BREAKING**: Switched from API Token to Global API Key authentication
- Updated API headers from `Authorization: Bearer` to `X-Auth-Email` and `X-Auth-Key`
- Updated configuration variables:
  - Removed: `CLOUDFLARE_API_TOKEN`
  - Added: `CLOUDFLARE_EMAIL` and `CLOUDFLARE_API_KEY`
- Updated DNS record name to full domain: `ranger0.home.elikesbikes.com`

### Fixed
- Log directory creation error when running without sudo
- Missing environment variable validation for Global API Key format
- Improved error messages for authentication failures

### Added
- Better debugging logs for API calls
- State tracking for last update time and IP
- More comprehensive configuration validation

## [1.0.0] - 2026-01-04

### Initial Release
- **Added**: Core Tailscale DNS updater functionality
- **Added**: Cloudflare API integration using API Tokens
- **Added**: Comprehensive logging system
- **Added**: Locking mechanism to prevent concurrent runs
- **Added**: IP comparison logic
- **Added**: Error handling and validation
- **Added**: Configuration via environment file
- **Added**: Support for Tailscale interface detection

### Features in Initial Release
- Automatic IP detection from Tailscale interface
- DNS record comparison with Cloudflare
- Secure API token authentication
- Log rotation via system services
- Detailed error messages for troubleshooting

## Technical Details

### Version 1.1.0 Configuration:
```bash
# Required variables
CLOUDFLARE_EMAIL="email@example.com"
CLOUDFLARE_API_KEY="global_api_key"
CLOUDFLARE_ZONE_ID="zone_id"
CLOUDFLARE_RECORD_ID="record_id"

# API Headers used
X-Auth-Email: ${CLOUDFLARE_EMAIL}
X-Auth-Key: ${CLOUDFLARE_API_KEY}