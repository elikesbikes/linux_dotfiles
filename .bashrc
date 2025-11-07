# ==============================================================================
# 1. Base Configuration & Non-Interactive Guard
# ==============================================================================

# Source base configuration (Must be first. MUST NOT produce output.)
source ~/.local/share/omakub/defaults/bash/rc

# CRITICAL FIX: Exit immediately if the shell is NOT interactive (e.g., scp, sftp).
# This prevents all output-generating code (like fastfetch) from running.
[[ $- != *i* ]] && return

# ==============================================================================
# 2. Interactive-Only Sourcing and Setup
# ==============================================================================

## Sourcing Custom Scripts
[[ -f ~/.bash/aliases.sh ]] && source ~/.bash/aliases.sh
[[ -f ~/.bash/starship.sh ]] && source ~/.bash/starship.sh
[[ -f ~/.bash/functions.sh ]] && source ~/.bash/functions.sh
[[ -f ~/.bash/misc.sh ]] && source ~/.bash/misc.sh

# Load Starship
eval "$(starship init bash)"

# Load direnv hook
eval "$(direnv hook bash)"

# Run output commands last
fastfetch

# ==============================================================================
# 3. Environment Variables (Order-independent)
# ==============================================================================

# Editor settings (Consolidated)
export EDITOR='nvim'
export VISUAL="$EDITOR"
export SUDO_EDITOR="$EDITOR"

# PATH Management (Recommended to use a function for cleaner PATH)
path_prepend() {
  if [[ ":$PATH:" != *":$1:"* ]]; then
    export PATH="$1${PATH:+:$PATH}"
  fi
}

# Add essential paths to the front of PATH for security and speed
path_prepend /bin
path_prepend /usr/bin

# Add custom paths (be sure '/usr/local/bin/bin' is needed)
path_prepend /usr/local/bin/bin/
path_prepend /usr/local/bin/
path_prepend /tmp
# Note: You need to define the 'path_prepend' function before the calls.

# ==============================================================================
# 4. Input Configuration
# ==============================================================================

# Bracketed Paste Mode (Safe as it uses the $PS1 check)
if [ -n "$PS1" ]; then
  bind 'set enable-bracketed-paste on'
fi

# Input
bind -f ~/.inputrc

