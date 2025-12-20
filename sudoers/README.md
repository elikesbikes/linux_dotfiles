Sudoers fragments (source-of-truth):
- 00-defaults: sudo Defaults (env_keep, future logging defaults)
- 10-admin: admin tools (docker/systemctl/chmod/chown)
- 20-diagnostics: crash troubleshooting tools
- 30-filesystem: read-only filesystem visibility
- 40-scripts: explicitly approved scripts allowed via sudo NOPASSWD

Deployed to: /etc/sudoers.d/
Installed by: /home/ecloaiza/scripts/linux/install-sudoers.sh

