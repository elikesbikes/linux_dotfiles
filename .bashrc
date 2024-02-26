##Running Shell scripts

[[ -f ~/.bash/aliases.sh ]] && source ~/.bash/aliases.sh
[[ -f ~/.bash/starship.sh ]] && source ~/.bash/starship.sh
[[ -f ~/.bash/functions.sh ]] && source ~/.bash/functions.sh
# Load Starship
eval "$(starship init bash)"

neofetch --config /home/ecloaiza/.config/neofetch/config.conf



eval "$(direnv hook bash)"

export PATH=$PATH:/usr/local/bin/bin/:/usr/local/bin/:/tmp