[[ -f ~/.bash/aliases.sh ]] && source ~/.bash/aliases.sh
[[ -f ~/.bash/starship.sh ]] && source ~/.bash/starship.sh
[[ -f ~/.bash/functions.sh ]] && source ~/.bash/functions.sh
# Load Starship
eval "$(starship init bash)"
