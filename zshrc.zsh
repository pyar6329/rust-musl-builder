# disable beep
setopt nobeep
# keybind is emacs style
bindkey -e
# use command without escape  symbol (&, ?)
setopt nonomatch
# case-insensitivity
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
# show completion menu
zstyle ':completion:*:default' menu select=1
# save zsh history
export HISTFILE="${HOME}/.zsh_history"
# history size
export HISTSIZE=100000
export SAVEHIST=1000000
# ignore duplicate history
setopt hist_ignore_dups
# share history
setopt share_history
# ignore space command
setopt hist_ignore_space
# ignore command start with white-space
setopt hist_reduce_blanks
# ignore all duplicate command
setopt hist_ignore_all_dups
# ignore /etc/profile
setopt no_global_rcs
# ignore duplicated path
typeset -U path manpath
# allow auto-completion
autoload -Uz compinit
compinit -C
# allow async prompt
zmodload zsh/zpty
# show time command like bash
export TIMEFMT=$'\n\n========================\nProgram : %J\nCPU     : %P\nuser    : %*Us\nsystem  : %*Ss\ntotal   : %*Es\n========================\n'
# enable starship
eval "$(starship init zsh)"
# enable docker
sudo service docker start
# add watch command
alias watch='watch '
