# Source global definitions
if [ -f /etc/bashrc ]; then
        . /etc/bashrc
fi

# User specific environment
if ! [[ "$PATH" =~ "$HOME/.local/bin:$HOME/bin:" ]]
then
    PATH="$HOME/.local/bin:$HOME/bin:$PATH"
fi
export PATH

# Uncomment the following line if you don't like systemctl's auto-paging feature:
# export SYSTEMD_PAGER=

# User specific aliases and functions
if [ -d ~/.bashrc.d ]; then
        for rc in ~/.bashrc.d/*; do
                if [ -f "$rc" ]; then
                        . "$rc"
                fi
        done
fi

unset rc

PS1='\[$(tput setaf 6)\]\@ \[\033[35;1m\]\u\[\033[0m\]@\[\033[31;1m\]\h \[\033[32;1m\]$PWD\[\033[0m\] [\[\033[35m\]\#\[\033[0m\]]\[\033[31m\]\$\[\033[0m\] '
[[ $- != *i* ]] && return

# User specific environment
if ! [[ "$PATH" =~ "$HOME/.local/bin:$HOME/bin:" ]]
then
    PATH="$HOME/.local/bin:$HOME/bin:$PATH"
fi
export PATH

# Uncomment the following line if you don't like systemctl's auto-paging feature:
# export SYSTEMD_PAGER=


# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000

echo -e -n "\E[1;34m"
figlet -w 50 "$(hostname)"
echo "├──Emmanuel Loaiza"
echo "├──ELIKESBIKES"
echo "└──"$(date +"%B%e"), $(date +"%Y")
uptime
echo -e "\E[0m"
alias vim="vi"
alias rm="rm -i"
alias U="cd .."
alias ls="ls -lA --color=yes | less -r -E -X"
alias cp="cp -ip"
alias mv="mv -i"
alias ll="ls -A | less -r -E -X"
alias pp="ping -c 3 google.com"
alias l="ll"
alias space="sudo du -h --max-depth=1"