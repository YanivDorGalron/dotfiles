# ──────────────────────────────────────────────
# .zshrc — portable (macOS + Linux, no root)
# ──────────────────────────────────────────────

# ── PATH ──
export PATH="$HOME/.local/bin:$HOME/.local/opt/go/bin:$HOME/go/bin:$HOME/.cargo/bin:$HOME/.fzf/bin:$HOME/.atuin/bin:$PATH"
# macOS homebrew (only exists on mac)
[ -d /opt/homebrew/bin ] && export PATH="/opt/homebrew/bin:$PATH"

# ── Terminal fixes ──
# Ensure backspace works correctly
stty erase '^?' 2>/dev/null
bindkey '^?' backward-delete-char
bindkey '^H' backward-delete-char

setopt prompt_subst
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
autoload bashcompinit && bashcompinit
autoload -Uz compinit
compinit

# kubectl completion
command -v kubectl &>/dev/null && source <(kubectl completion zsh)

# zsh-autosuggestions (try all known paths)
for _zas in \
    "$(brew --prefix 2>/dev/null)/share/zsh-autosuggestions/zsh-autosuggestions.zsh" \
    "$HOME/.local/share/zsh-autosuggestions/zsh-autosuggestions.zsh" \
    "/usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh" \
    "/usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"; do
    [ -f "$_zas" ] && { source "$_zas"; break; }
done
unset _zas
bindkey '^w' autosuggest-execute
bindkey '^e' autosuggest-accept
bindkey '^u' autosuggest-toggle
bindkey '^L' vi-forward-word
bindkey '^k' up-line-or-search
bindkey '^j' down-line-or-search

# Starship
eval "$(starship init zsh)"
export STARSHIP_CONFIG=~/.config/starship/starship.toml

export LANG=en_US.UTF-8
export EDITOR=nvim
export XDG_CONFIG_HOME="$HOME/.config"

# ── Aliases ──
alias la=tree
alias cat=bat
alias cl='clear'

# Git
alias gc="git commit -m"
alias gca="git commit -a -m"
alias gp="git push origin HEAD"
alias gpu="git pull origin"
alias gst="git status"
alias glog="git log --graph --topo-order --pretty='%w(100,0,6)%C(yellow)%h%C(bold)%C(black)%d %C(cyan)%ar %C(green)%an%n%C(bold)%C(white)%s %N' --abbrev-commit"
alias gdiff="git diff"
alias gco="git checkout"
alias gb='git branch'
alias gba='git branch -a'
alias gadd='git add'
alias ga='git add -p'
alias gcoall='git checkout -- .'
alias gre='git reset'

# Docker
alias dco="docker compose"
alias dps="docker ps"
alias dpa="docker ps -a"
alias dl="docker ps -l -q"
alias dx="docker exec -it"

# Dirs
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias .....="cd ../../../.."
alias ......="cd ../../../../.."

# GO
export GOPATH="$HOME/go"

# VIM
alias v=nvim

# Nmap
alias nm="nmap -sC -sV -oN nmap"

# K8S
export KUBECONFIG=~/.kube/config
alias k="kubectl"
alias ka="kubectl apply -f"
alias kg="kubectl get"
alias kd="kubectl describe"
alias kdel="kubectl delete"
alias kl="kubectl logs -f"
alias kgpo="kubectl get pod"
alias kgd="kubectl get deployments"
alias kc="kubectx"
alias kns="kubens"
alias ke="kubectl exec -it"
alias kcns='kubectl config set-context --current --namespace'

# HTTP requests with xh
alias http="xh"

# VI Mode
bindkey jj vi-cmd-mode

# Eza
alias l="eza -l --icons --git -a"
alias lt="eza --tree --level=2 --long --icons --git"
alias ltree="eza --tree --level=2 --icons --git"

# SEC STUFF
alias server='python3 -m http.server 4445'

# FZF
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow'
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Ranger (cd on quit)
function ranger {
    local IFS=$'\t\n'
    local tempfile="$(mktemp -t tmp.XXXXXX)"
    local ranger_cmd=(
        command
        ranger
        --cmd="map Q chain shell echo %d > "$tempfile"; quitall"
    )
    ${ranger_cmd[@]} "$@"
    if [[ -f "$tempfile" ]] && [[ "$(cat -- "$tempfile")" != "$(echo -n $(pwd))" ]]; then
        cd -- "$(cat "$tempfile")" || return
    fi
    command rm -f -- "$tempfile" 2>/dev/null
}
alias rr='ranger'

# Navigation — clipboard: pbcopy on mac, xclip on linux
_clip() { command -v pbcopy &>/dev/null && pbcopy || xclip -selection clipboard 2>/dev/null; }
cx() { cd "$@" && l; }
fcd() { cd "$(find . -type d -not -path '*/.*' | fzf)" && l; }
f() { echo "$(find . -type f -not -path '*/.*' | fzf)" | _clip; }
fv() { nvim "$(find . -type f -not -path '*/.*' | fzf)"; }

# Nix (if installed)
if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
    . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
fi
export NIX_CONF_DIR=$HOME/.config/nix

# NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

# Tool initializations (lazy — only if installed)
command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"
command -v atuin  &>/dev/null && eval "$(atuin init zsh)"
command -v direnv &>/dev/null && eval "$(direnv hook zsh)"
