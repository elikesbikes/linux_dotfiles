alias vim="nvim"
alias vi="nvim"
alias rm="rm -i"
alias U="cd .."
alias cp="cp -ip"
alias mv="mv -i"
alias l="eza -lgho --sort=modified --icons --git --git-repos"
alias ls="eza -lgho --sort=modified  --icons --git --git-repos"
alias ll="eza -lgho --sort=modified --icons --git --git-repos"
alias pp="ping -c 3 google.com"
alias space="sudo du -h --max-depth=1 -t 1G"
alias dot="yadm pull"
alias docker-restart='docker restart $(docker ps -a -q)'
alias dockerrun="sudo docker ps --format 'table {{.ID}}\t{{.Names}}\t{{.Status}}'"
alias dockerlogs="sudo docker compose logs -f"
alias takeover="sudo chown -R ecloaiza:ecloaiza *"
alias fixperm="sudo chmod -R 775 *"
alias idrive="/opt/IDriveForLinux/bin/idrive"
alias sudoers="$HOME/scripts/linux/install-sudoers.sh"
# syncn moved to functions.sh (aliases don't expand inside functions)
alias syncs='$HOME/scripts/linux/sudoers/sync-sudoers.sh'
alias sync_claude='unison claude_skills'
claudepower() { cd $HOME/devops/ubuntu && claude --enable-auto-mode --dangerously-skip-permissions "$@"; }
codexpower() { cd $HOME/devops/ubuntu && codex --dangerously-bypass-approvals-and-sandbox "$@"; }
alias claudemddocker='rm -f CLAUDE.md && ln -s "$HOME/devops/github/adastra/AI/prompts/CLAUDE-docker.md" CLAUDE.md'
alias claudedocker='rm -f CLAUDE-docker.md && ln -s "$HOME/devops/github/adastra/AI/prompts/CLAUDE-docker.md" CLAUDE-docker.md'
alias cleanupdotfiles='rm -rf $HOME/devops/github/linux_dotfiles/ && cd $HOME/devops/github && git clone https://github.com/elikesbikes/linux_dotfiles.git'
alias upgraderustdesk='wget -O /tmp/rustdesk.deb "$(curl -s https://api.github.com/repos/rustdesk/rustdesk/releases/latest | grep -o '\''https://[^"]*x86_64\.deb'\'' | head -1)" && sudo apt install -y /tmp/rustdesk.deb'
alias repopullforce='git fetch --all && git reset --hard origin/$(git rev-parse --abbrev-ref HEAD) && git pull'
