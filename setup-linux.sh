#!/usr/bin/env bash
#
# Linux Setup Script (NO ROOT REQUIRED)
# Replicates the macOS dotfiles environment on a Linux server.
# Everything is installed under $HOME (~/.local/bin, ~/.local/share, etc.)
#
# Usage: chmod +x linux-setup.sh && ./linux-setup.sh
#
set -euo pipefail

# ──────────────────────────────────────────────
# Paths — everything under $HOME
# ──────────────────────────────────────────────
LOCAL_BIN="$HOME/.local/bin"
LOCAL_SHARE="$HOME/.local/share"
LOCAL_OPT="$HOME/.local/opt"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

mkdir -p "$LOCAL_BIN" "$LOCAL_SHARE" "$LOCAL_OPT" "$XDG_CONFIG_HOME"

export PATH="$LOCAL_BIN:$HOME/.local/opt/go/bin:$HOME/go/bin:$HOME/.nvm/versions/node/*/bin:$PATH"

# ──────────────────────────────────────────────
# Colors
# ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERR ]${NC} $*"; }

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ARCH_GO="amd64"; ARCH_ALT="x86_64"; ARCH_NVIM="x86_64" ;;
    aarch64) ARCH_GO="arm64"; ARCH_ALT="aarch64"; ARCH_NVIM="arm64" ;;
    *)       err "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Helper: download a GitHub release binary and put it in ~/.local/bin
# Usage: gh_install_binary <repo> <asset_pattern> [<binary_name_inside_archive>]
gh_install_binary() {
    local repo="$1" pattern="$2" bin_name="${3:-}"
    local url
    url=$(curl -sL "https://api.github.com/repos/${repo}/releases/latest" \
        | grep -oP '"browser_download_url":\s*"\K[^"]*'"${pattern}"'[^"]*' \
        | head -1)
    if [ -z "$url" ]; then
        warn "Could not find release asset for $repo matching '$pattern'"
        return 1
    fi
    local tmp="/tmp/gh_install_$$"
    mkdir -p "$tmp"
    local filename
    filename=$(basename "$url")
    curl -sL -o "$tmp/$filename" "$url"
    case "$filename" in
        *.tar.gz|*.tgz)
            tar -xzf "$tmp/$filename" -C "$tmp"
            ;;
        *.tar.xz)
            tar -xJf "$tmp/$filename" -C "$tmp"
            ;;
        *.zip)
            unzip -qo "$tmp/$filename" -d "$tmp"
            ;;
        *)
            # Assume it's a raw binary
            chmod +x "$tmp/$filename"
            mv "$tmp/$filename" "$LOCAL_BIN/${bin_name:-$(basename "$repo")}"
            rm -rf "$tmp"
            return 0
            ;;
    esac
    # Find and install the binary
    if [ -n "$bin_name" ]; then
        local found
        found=$(find "$tmp" -name "$bin_name" -type f | head -1)
        if [ -n "$found" ]; then
            chmod +x "$found"
            mv "$found" "$LOCAL_BIN/$bin_name"
        fi
    fi
    rm -rf "$tmp"
}

# ──────────────────────────────────────────────
# Zsh (from source if not available)
# ──────────────────────────────────────────────
install_zsh() {
    if command -v zsh &>/dev/null; then
        ok "zsh already available at $(which zsh)"
        return
    fi
    info "Building zsh from source into ~/.local ..."
    local tmp="/tmp/zsh_build_$$"
    mkdir -p "$tmp"
    local version="5.9.1"
    # Use GitHub mirror (SourceForge redirects break curl)
    curl -sL "https://github.com/zsh-users/zsh/archive/refs/tags/zsh-${version}.tar.gz" -o "$tmp/zsh.tar.gz"
    tar -xzf "$tmp/zsh.tar.gz" -C "$tmp"
    cd "$tmp/zsh-zsh-${version}"
    # autoconf is needed for GitHub source (no pre-generated configure)
    if [ -f Util/preconfig ]; then
        ./Util/preconfig
    elif command -v autoconf &>/dev/null; then
        autoheader && autoconf
    else
        err "autoconf not available — cannot build zsh from source"
        err "Ask your admin to install zsh, or install autoconf"
        cd - >/dev/null; rm -rf "$tmp"
        return 1
    fi
    ./configure --prefix="$HOME/.local" --enable-multibyte --without-tcsetpgrp
    make -j"$(nproc)" && make install
    cd - >/dev/null
    rm -rf "$tmp"
    ok "zsh built and installed at $LOCAL_BIN/zsh"
}

# ──────────────────────────────────────────────
# zsh-autosuggestions
# ──────────────────────────────────────────────
install_zsh_autosuggestions() {
    local dest="$LOCAL_SHARE/zsh-autosuggestions"
    if [ -d "$dest" ]; then
        ok "zsh-autosuggestions already installed"
        return
    fi
    info "Installing zsh-autosuggestions..."
    git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions.git "$dest"
    ok "zsh-autosuggestions installed"
}

# ──────────────────────────────────────────────
# Stow
# ──────────────────────────────────────────────
install_stow() {
    if command -v stow &>/dev/null; then
        ok "stow already available"
        return
    fi
    info "Installing stow from source..."
    local tmp="/tmp/stow_build_$$"
    mkdir -p "$tmp"
    curl -sL "https://ftp.gnu.org/gnu/stow/stow-latest.tar.gz" -o "$tmp/stow.tar.gz"
    tar -xzf "$tmp/stow.tar.gz" -C "$tmp"
    cd "$tmp"/stow-*/
    ./configure --prefix="$HOME/.local"
    make && make install
    cd - >/dev/null
    rm -rf "$tmp"
    ok "stow installed"
}

# ──────────────────────────────────────────────
# tmux (from AppImage or source)
# ──────────────────────────────────────────────
install_tmux() {
    if command -v tmux &>/dev/null; then
        ok "tmux already available ($(tmux -V))"
        return
    fi
    info "Installing tmux AppImage..."
    local url="https://github.com/nelsonenzo/tmux-appimage/releases/latest/download/tmux.appimage"
    curl -sL -o "$LOCAL_BIN/tmux.appimage" "$url"
    chmod +x "$LOCAL_BIN/tmux.appimage"
    # Try to extract if FUSE is not available
    if ! "$LOCAL_BIN/tmux.appimage" --version &>/dev/null 2>&1; then
        info "FUSE not available, extracting AppImage..."
        cd "$LOCAL_BIN"
        ./tmux.appimage --appimage-extract &>/dev/null
        ln -sf "$LOCAL_BIN/squashfs-root/usr/bin/tmux" "$LOCAL_BIN/tmux"
        rm -f "$LOCAL_BIN/tmux.appimage"
        cd - >/dev/null
    else
        ln -sf "$LOCAL_BIN/tmux.appimage" "$LOCAL_BIN/tmux"
    fi
    ok "tmux installed"
}

# ──────────────────────────────────────────────
# Neovim
# ──────────────────────────────────────────────
install_neovim() {
    if command -v nvim &>/dev/null; then
        ok "Neovim already installed ($(nvim --version | head -1))"
        return
    fi
    info "Installing Neovim..."
    local url="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${ARCH_NVIM}.tar.gz"
    curl -sL -o /tmp/nvim.tar.gz "$url"
    rm -rf "$LOCAL_OPT/nvim"
    mkdir -p "$LOCAL_OPT/nvim"
    tar -xzf /tmp/nvim.tar.gz -C "$LOCAL_OPT/nvim" --strip-components=1
    ln -sf "$LOCAL_OPT/nvim/bin/nvim" "$LOCAL_BIN/nvim"
    rm /tmp/nvim.tar.gz
    ok "Neovim installed"
}

# ──────────────────────────────────────────────
# Git (check it exists, it's almost always on servers)
# ──────────────────────────────────────────────
check_git() {
    if command -v git &>/dev/null; then
        ok "git available ($(git --version))"
    else
        err "git is not installed and cannot be installed without root. Ask your admin."
        exit 1
    fi
}

# ──────────────────────────────────────────────
# Go
# ──────────────────────────────────────────────
install_go() {
    if command -v go &>/dev/null; then
        ok "Go already installed ($(go version))"
        return
    fi
    info "Installing Go..."
    local go_version
    go_version=$(curl -sL 'https://go.dev/VERSION?m=text' | head -1)
    curl -sL -o /tmp/go.tar.gz "https://go.dev/dl/${go_version}.linux-${ARCH_GO}.tar.gz"
    rm -rf "$LOCAL_OPT/go"
    mkdir -p "$LOCAL_OPT/go"
    tar -xzf /tmp/go.tar.gz -C "$LOCAL_OPT" # extracts to $LOCAL_OPT/go
    ln -sf "$LOCAL_OPT/go/bin/go" "$LOCAL_BIN/go"
    ln -sf "$LOCAL_OPT/go/bin/gofmt" "$LOCAL_BIN/gofmt"
    rm /tmp/go.tar.gz
    ok "Go installed ($go_version)"
}

# ──────────────────────────────────────────────
# Node.js via nvm (user-local)
# ──────────────────────────────────────────────
install_node() {
    if command -v node &>/dev/null; then
        ok "Node.js already installed ($(node --version))"
        return
    fi
    info "Installing Node.js via nvm..."
    export NVM_DIR="$HOME/.nvm"
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    nvm install --lts
    ok "Node.js installed ($(node --version))"
}

# ──────────────────────────────────────────────
# Starship
# ──────────────────────────────────────────────
install_starship() {
    if command -v starship &>/dev/null; then
        ok "Starship already installed"
        return
    fi
    info "Installing Starship..."
    curl -sS https://starship.rs/install.sh | sh -s -- --bin-dir "$LOCAL_BIN" -y
    ok "Starship installed"
}

# ──────────────────────────────────────────────
# fzf
# ──────────────────────────────────────────────
install_fzf() {
    if command -v fzf &>/dev/null; then
        ok "fzf already installed"
        return
    fi
    info "Installing fzf..."
    git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
    "$HOME/.fzf/install" --bin
    ln -sf "$HOME/.fzf/bin/fzf" "$LOCAL_BIN/fzf"
    ok "fzf installed"
}

# ──────────────────────────────────────────────
# fd
# ──────────────────────────────────────────────
install_fd() {
    if command -v fd &>/dev/null; then
        ok "fd already installed"
        return
    fi
    info "Installing fd..."
    gh_install_binary "sharkdp/fd" "x86_64-unknown-linux-musl.tar.gz" "fd"
    if [ "$ARCH" = "aarch64" ]; then
        gh_install_binary "sharkdp/fd" "aarch64-unknown-linux-gnu.tar.gz" "fd"
    fi
    ok "fd installed"
}

# ──────────────────────────────────────────────
# bat
# ──────────────────────────────────────────────
install_bat() {
    if command -v bat &>/dev/null; then
        ok "bat already installed"
        return
    fi
    info "Installing bat..."
    gh_install_binary "sharkdp/bat" "x86_64-unknown-linux-musl.tar.gz" "bat"
    if [ "$ARCH" = "aarch64" ]; then
        gh_install_binary "sharkdp/bat" "aarch64-unknown-linux-gnu.tar.gz" "bat"
    fi
    ok "bat installed"
}

# ──────────────────────────────────────────────
# ripgrep
# ──────────────────────────────────────────────
install_ripgrep() {
    if command -v rg &>/dev/null; then
        ok "ripgrep already installed"
        return
    fi
    info "Installing ripgrep..."
    gh_install_binary "BurntSushi/ripgrep" "x86_64-unknown-linux-musl.tar.gz" "rg"
    if [ "$ARCH" = "aarch64" ]; then
        gh_install_binary "BurntSushi/ripgrep" "aarch64-unknown-linux-gnu.tar.gz" "rg"
    fi
    ok "ripgrep installed"
}

# ──────────────────────────────────────────────
# eza
# ──────────────────────────────────────────────
install_eza() {
    if command -v eza &>/dev/null; then
        ok "eza already installed"
        return
    fi
    info "Installing eza..."
    gh_install_binary "eza-community/eza" "x86_64-unknown-linux-musl.tar.gz" "eza"
    if [ "$ARCH" = "aarch64" ]; then
        gh_install_binary "eza-community/eza" "aarch64-unknown-linux-gnu.tar.gz" "eza"
    fi
    ok "eza installed"
}

# ──────────────────────────────────────────────
# tree
# ──────────────────────────────────────────────
check_tree() {
    if command -v tree &>/dev/null; then
        ok "tree already available"
    else
        warn "tree not available — 'la' alias won't work (non-critical)"
    fi
}

# ──────────────────────────────────────────────
# jq
# ──────────────────────────────────────────────
install_jq() {
    if command -v jq &>/dev/null; then
        ok "jq already installed"
        return
    fi
    info "Installing jq..."
    local jq_arch="amd64"
    [ "$ARCH" = "aarch64" ] && jq_arch="arm64"
    local url
    url=$(curl -sL "https://api.github.com/repos/jqlang/jq/releases/latest" \
        | grep -oP '"browser_download_url":\s*"\K[^"]*linux-'"$jq_arch"'[^"]*' \
        | head -1)
    curl -sL -o "$LOCAL_BIN/jq" "$url"
    chmod +x "$LOCAL_BIN/jq"
    ok "jq installed"
}

# ──────────────────────────────────────────────
# zoxide
# ──────────────────────────────────────────────
install_zoxide() {
    if command -v zoxide &>/dev/null; then
        ok "zoxide already installed"
        return
    fi
    info "Installing zoxide..."
    curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
    # zoxide installer puts it in ~/.local/bin by default
    ok "zoxide installed"
}

# ──────────────────────────────────────────────
# atuin
# ──────────────────────────────────────────────
install_atuin() {
    if command -v atuin &>/dev/null; then
        ok "atuin already installed"
        return
    fi
    info "Installing atuin..."
    curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh
    ok "atuin installed"
}

# ──────────────────────────────────────────────
# direnv
# ──────────────────────────────────────────────
install_direnv() {
    if command -v direnv &>/dev/null; then
        ok "direnv already installed"
        return
    fi
    info "Installing direnv..."
    local direnv_arch="amd64"
    [ "$ARCH" = "aarch64" ] && direnv_arch="arm64"
    curl -sL -o "$LOCAL_BIN/direnv" "https://github.com/direnv/direnv/releases/latest/download/direnv.linux-${direnv_arch}"
    chmod +x "$LOCAL_BIN/direnv"
    ok "direnv installed"
}

# ──────────────────────────────────────────────
# xh (HTTP client)
# ──────────────────────────────────────────────
install_xh() {
    if command -v xh &>/dev/null; then
        ok "xh already installed"
        return
    fi
    info "Installing xh..."
    gh_install_binary "ducaale/xh" "x86_64-unknown-linux-musl.tar.gz" "xh"
    if [ "$ARCH" = "aarch64" ]; then
        gh_install_binary "ducaale/xh" "aarch64-unknown-linux-musl.tar.gz" "xh"
    fi
    ok "xh installed"
}

# ──────────────────────────────────────────────
# ranger
# ──────────────────────────────────────────────
install_ranger() {
    if command -v ranger &>/dev/null; then
        ok "ranger already installed"
        return
    fi
    info "Installing ranger via pip..."
    pip3 install --user ranger-fm
    ok "ranger installed"
}

# ──────────────────────────────────────────────
# kubectl
# ──────────────────────────────────────────────
install_kubectl() {
    if command -v kubectl &>/dev/null; then
        ok "kubectl already installed"
        return
    fi
    info "Installing kubectl..."
    local kube_version
    kube_version=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    curl -sL -o "$LOCAL_BIN/kubectl" "https://dl.k8s.io/release/${kube_version}/bin/linux/${ARCH_GO}/kubectl"
    chmod +x "$LOCAL_BIN/kubectl"
    ok "kubectl installed ($kube_version)"
}

# ──────────────────────────────────────────────
# kubectx + kubens
# ──────────────────────────────────────────────
install_kubectx() {
    if command -v kubectx &>/dev/null; then
        ok "kubectx already installed"
        return
    fi
    info "Installing kubectx + kubens..."
    local version
    version=$(curl -sL https://api.github.com/repos/ahmetb/kubectx/releases/latest | jq -r '.tag_name')
    curl -sL -o /tmp/kubectx.tar.gz "https://github.com/ahmetb/kubectx/releases/download/${version}/kubectx_${version}_linux_${ARCH_ALT}.tar.gz"
    curl -sL -o /tmp/kubens.tar.gz "https://github.com/ahmetb/kubectx/releases/download/${version}/kubens_${version}_linux_${ARCH_ALT}.tar.gz"
    tar -xzf /tmp/kubectx.tar.gz -C "$LOCAL_BIN" kubectx
    tar -xzf /tmp/kubens.tar.gz -C "$LOCAL_BIN" kubens
    rm /tmp/kubectx.tar.gz /tmp/kubens.tar.gz
    ok "kubectx + kubens installed ($version)"
}

# ──────────────────────────────────────────────
# Helm
# ──────────────────────────────────────────────
install_helm() {
    if command -v helm &>/dev/null; then
        ok "Helm already installed"
        return
    fi
    info "Installing Helm..."
    local tmp="/tmp/helm_install_$$"
    mkdir -p "$tmp"
    curl -sL "https://get.helm.sh/helm-$(curl -sL https://api.github.com/repos/helm/helm/releases/latest | jq -r '.tag_name')-linux-${ARCH_GO}.tar.gz" -o "$tmp/helm.tar.gz"
    tar -xzf "$tmp/helm.tar.gz" -C "$tmp"
    mv "$tmp/linux-${ARCH_GO}/helm" "$LOCAL_BIN/helm"
    chmod +x "$LOCAL_BIN/helm"
    rm -rf "$tmp"
    ok "Helm installed"
}

# ──────────────────────────────────────────────
# Terraform
# ──────────────────────────────────────────────
install_terraform() {
    if command -v terraform &>/dev/null; then
        ok "Terraform already installed"
        return
    fi
    info "Installing Terraform..."
    local version
    version=$(curl -sL https://api.github.com/repos/hashicorp/terraform/releases/latest | jq -r '.tag_name' | sed 's/^v//')
    curl -sL -o /tmp/terraform.zip "https://releases.hashicorp.com/terraform/${version}/terraform_${version}_linux_${ARCH_GO}.zip"
    unzip -qo /tmp/terraform.zip -d "$LOCAL_BIN"
    chmod +x "$LOCAL_BIN/terraform"
    rm /tmp/terraform.zip
    ok "Terraform installed ($version)"
}

# ──────────────────────────────────────────────
# JetBrains Mono Nerd Font (user-local)
# ──────────────────────────────────────────────
install_nerd_font() {
    local font_dir="$LOCAL_SHARE/fonts"
    if ls "$font_dir"/JetBrains* &>/dev/null 2>&1; then
        ok "JetBrains Mono Nerd Font already installed"
        return
    fi
    info "Installing JetBrains Mono Nerd Font..."
    mkdir -p "$font_dir"
    local version
    version=$(curl -sL https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest | jq -r '.tag_name')
    curl -sL -o /tmp/JetBrainsMono.tar.xz "https://github.com/ryanoasis/nerd-fonts/releases/download/${version}/JetBrainsMono.tar.xz"
    tar -xJf /tmp/JetBrainsMono.tar.xz -C "$font_dir"
    # fc-cache if available (not critical on a server)
    command -v fc-cache &>/dev/null && fc-cache -f "$font_dir" 2>/dev/null || true
    rm /tmp/JetBrainsMono.tar.xz
    ok "JetBrains Mono Nerd Font installed at $font_dir"
}

# ──────────────────────────────────────────────
# TPM (Tmux Plugin Manager)
# ──────────────────────────────────────────────
install_tpm() {
    if [ -d "$HOME/.tmux/plugins/tpm" ]; then
        ok "TPM already installed"
        return
    fi
    info "Installing TPM (Tmux Plugin Manager)..."
    git clone --depth 1 https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
    ok "TPM installed"
}

# ──────────────────────────────────────────────
# Clone dotfiles & stow
# ──────────────────────────────────────────────
setup_dotfiles() {
    local dotfiles_dir="$HOME/dotfiles"
    if [ -d "$dotfiles_dir" ]; then
        info "Dotfiles directory already exists, pulling latest..."
        git -C "$dotfiles_dir" pull || warn "Could not pull dotfiles, using existing"
    else
        info "Cloning dotfiles..."
        git clone https://github.com/YanivDorGalron/dotfiles.git "$dotfiles_dir"
    fi
    ok "Dotfiles ready at $dotfiles_dir"
}

stow_dotfiles() {
    local dotfiles_dir="$HOME/dotfiles"
    info "Stowing dotfiles into ~/.config ..."
    mkdir -p "$XDG_CONFIG_HOME"

    # Cross-platform configs
    local stow_packages=(
        nvim
        tmux
        starship
        zellij
        nushell
        nix
    )

    cd "$dotfiles_dir"
    for pkg in "${stow_packages[@]}"; do
        if [ -d "$pkg" ]; then
            stow --target="$XDG_CONFIG_HOME" --ignore='DS_Store' --ignore='atuin/.*' "$pkg" 2>/dev/null \
                && ok "Stowed $pkg" \
                || warn "Stow conflict for $pkg — remove existing files in ~/.config/$pkg first"
        fi
    done
    cd - >/dev/null
}

# ──────────────────────────────────────────────
# Symlink .zshrc from dotfiles to ~
# ──────────────────────────────────────────────
link_zshrc() {
    local dotfiles_dir="$HOME/dotfiles"
    if [ -f "$dotfiles_dir/zshrc/.zshrc" ]; then
        ln -sf "$dotfiles_dir/zshrc/.zshrc" "$HOME/.zshrc"
        ok "Symlinked ~/.zshrc -> dotfiles/zshrc/.zshrc"
    else
        warn ".zshrc not found in dotfiles"
    fi
}

# ──────────────────────────────────────────────
# .gitconfig
# ──────────────────────────────────────────────
setup_gitconfig() {
    if [ -f "$HOME/.gitconfig" ]; then
        ok "~/.gitconfig already exists, skipping"
        return
    fi
    info "Creating ~/.gitconfig..."
    cat > "$HOME/.gitconfig" << 'EOF'
[user]
	email = yaniv.galron@campus.technion.ac.il
	name = Yaniv Galron
EOF
    ok "~/.gitconfig created"
}

# ──────────────────────────────────────────────
# Ghostty terminfo (for proper terminal support over SSH)
# Run this FROM YOUR MAC before SSHing: infocmp -x xterm-ghostty | ssh <host> 'tic -x -'
# This function sets up the terminfo if it was already transferred
# ──────────────────────────────────────────────
setup_terminfo() {
    if [ -d "$HOME/.terminfo" ] && ls "$HOME/.terminfo"/*/xterm-ghostty &>/dev/null 2>&1; then
        ok "Ghostty terminfo already present"
    else
        warn "Ghostty terminfo not found. Run this FROM YOUR MAC to install it:"
        echo "    infocmp -x xterm-ghostty | ssh <this-host> 'tic -x -'"
    fi
}

# ──────────────────────────────────────────────
# Shell setup (without root/chsh)
# ──────────────────────────────────────────────
setup_shell_login() {
    local zsh_path
    zsh_path=$(command -v zsh 2>/dev/null || echo "$LOCAL_BIN/zsh")

    # If we can't chsh, add exec zsh to .bash_profile so login drops into zsh
    if [ "$SHELL" != "$zsh_path" ]; then
        info "Cannot chsh without root. Adding 'exec zsh' to ~/.bash_profile..."
        local marker="# auto-exec zsh"
        if ! grep -q "$marker" "$HOME/.bash_profile" 2>/dev/null; then
            cat >> "$HOME/.bash_profile" << EOF

$marker
if command -v zsh &>/dev/null && [ -z "\$ZSH_VERSION" ]; then
    export SHELL=\$(command -v zsh)
    exec zsh -l
fi
EOF
            ok "Added zsh exec to ~/.bash_profile"
        else
            ok "zsh exec already in ~/.bash_profile"
        fi
        # Same for .profile (some systems use this)
        if [ -f "$HOME/.profile" ] && ! grep -q "$marker" "$HOME/.profile" 2>/dev/null; then
            cat >> "$HOME/.profile" << EOF

$marker
if command -v zsh &>/dev/null && [ -z "\$ZSH_VERSION" ]; then
    export SHELL=\$(command -v zsh)
    exec zsh -l
fi
EOF
        fi
    fi
}

# ──────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────
print_summary() {
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Setup Complete! (all under \$HOME)${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
    echo ""
    echo "Everything installed in:"
    echo "  Binaries:  ~/.local/bin"
    echo "  Runtimes:  ~/.local/opt/{go,nvim}"
    echo "  Configs:   ~/.config/{nvim,tmux,starship,...}"
    echo "  Fonts:     ~/.local/share/fonts"
    echo ""
    echo "Next steps:"
    echo "  1. Log out and back in (or run 'exec zsh') for your new shell"
    echo "  2. Open tmux and press '§ + I' to install tmux plugins via TPM"
    echo "  3. Open nvim — LazyVim will auto-install plugins on first launch"
    echo ""
    echo "Skipped (macOS-only):"
    echo "  aerospace, skhd, sketchybar, hammerspoon, karabiner, borders, ghostty, wezterm"
    echo ""
    echo -e "${YELLOW}Note:${NC} If zsh was not on the system, it was built from source."
    echo "      Your bash_profile now auto-execs zsh on login."
    echo ""
}

# ──────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────
main() {
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Linux Environment Setup (no root)${NC}"
    echo -e "${CYAN}  Everything installs under \$HOME${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
    echo ""

    check_git
    install_zsh
    install_zsh_autosuggestions
    install_stow
    install_jq
    install_neovim
    install_tmux
    install_go
    install_node
    install_fd
    install_bat
    install_ripgrep
    install_eza
    install_fzf
    install_starship
    install_zoxide
    install_atuin
    install_direnv
    install_xh
    install_ranger
    install_kubectl
    install_kubectx
    install_helm
    install_terraform
    install_nerd_font
    install_tpm
    setup_dotfiles
    stow_dotfiles
    link_zshrc
    setup_gitconfig
    setup_shell_login
    setup_terminfo
    check_tree

    print_summary
}

main "$@"
