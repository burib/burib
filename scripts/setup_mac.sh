#!/bin/bash
# Set up a new Mac with my tools, shell, and Terminal profiles.
#
# Usage - one-liner on a fresh Mac (clones this repo by itself):
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/burib/burib/main/scripts/setup_mac.sh)"
# or from a checkout:
#   ./scripts/setup_mac.sh
#
# Idempotent: safe to re-run at any time. Installs Homebrew + everything in
# ../Brewfile, Claude Code, node (nvm) and tofu (tofuenv), then copies the
# dotfiles and Terminal profiles from this repo into place.
set -euo pipefail

REPO_URL="https://github.com/burib/burib.git"

log() { printf '\n==> %s\n' "$*"; }

# --- Xcode Command Line Tools (compilers, git) ---
if ! xcode-select -p >/dev/null 2>&1; then
  log "Installing Xcode Command Line Tools - accept the dialog, then re-run this script"
  xcode-select --install
  exit 0
fi

# --- Locate the repo; when run via the curl one-liner, clone it first ---
# (git is available here: the CLT check above guarantees it)
SCRIPT_SRC="${BASH_SOURCE[0]:-}"
if [ -n "$SCRIPT_SRC" ] && [ -f "$SCRIPT_SRC" ] && [ -f "$(dirname "$SCRIPT_SRC")/../Brewfile" ]; then
  REPO_DIR="$(cd "$(dirname "$SCRIPT_SRC")/.." && pwd)"
else
  REPO_DIR="$HOME/dev/burib/burib"
  if [ -d "$REPO_DIR/.git" ]; then
    log "Updating existing checkout in $REPO_DIR"
    git -C "$REPO_DIR" pull --ff-only || true
  else
    log "Cloning $REPO_URL into $REPO_DIR"
    mkdir -p "$(dirname "$REPO_DIR")"
    git clone "$REPO_URL" "$REPO_DIR"
  fi
fi

# --- Homebrew ---
if ! command -v brew >/dev/null 2>&1 && [ ! -x /opt/homebrew/bin/brew ]; then
  log "Installing Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$(/opt/homebrew/bin/brew shellenv)"

# --- Packages, apps, fonts ---
# Newer brew refuses to install from untrusted third-party taps; trust the
# ones the Brewfile relies on (freeze lives in charmbracelet/tap).
# `|| true`: older brew has no `trust` command and needs none.
brew trust charmbracelet/tap 2>/dev/null || true

# The Brewfile also lists global npm/go packages; those need node/go, so a
# failing first pass is retried once node (via nvm) is in place.
log "Installing Homebrew packages"
# --no-upgrade: install what's missing but never upgrade what's already
# there - re-runs must not turn into surprise multi-GB upgrades (mactex...)
bundle_ok=1
brew bundle install --no-upgrade --file "$REPO_DIR/Brewfile" || bundle_ok=0

# --- node via nvm (nvm never installs a node by itself) ---
export NVM_DIR="$HOME/.nvm"
mkdir -p "$NVM_DIR"
[ -s /opt/homebrew/opt/nvm/nvm.sh ] && source /opt/homebrew/opt/nvm/nvm.sh
if command -v nvm >/dev/null 2>&1 && ! command -v node >/dev/null 2>&1; then
  log "Installing node LTS via nvm"
  nvm install --lts
fi
# A single flaky package must not block the dotfiles/profile steps below;
# brew bundle is idempotent, so failures here are fixed by re-running later.
if [ "$bundle_ok" = 0 ]; then
  log "Re-running brew bundle (npm/go globals needed node/go)"
  brew bundle install --no-upgrade --file "$REPO_DIR/Brewfile" \
    || log "WARNING: some Brewfile entries failed - re-run this script later"
fi

# --- tofu via tofuenv ---
if command -v tofuenv >/dev/null 2>&1 && ! command -v tofu >/dev/null 2>&1; then
  log "Installing OpenTofu via tofuenv"
  tofuenv install latest
  tofuenv use latest
fi

# --- Claude Code (native installer, lands in ~/.local/bin) ---
if ! command -v claude >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/claude" ]; then
  log "Installing Claude Code"
  curl -fsSL https://claude.ai/install.sh | bash
fi

# --- git defaults ---
git config --global --add --bool push.autoSetupRemote true

# --- Dotfiles (an existing file that differs is backed up next to itself) ---
log "Installing dotfiles"
install_file() {
  local src="$REPO_DIR/$1" dest="$2"
  if [ -f "$dest" ] && ! cmp -s "$src" "$dest"; then
    cp "$dest" "$dest.backup.$(date +%Y%m%d%H%M%S)"
    echo "    backed up existing $dest"
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  echo "    $dest"
}
install_file dotfiles/zshrc                       "$HOME/.zshrc"
install_file dotfiles/aws_profile.sh              "$HOME/aws_profile.sh"
install_file dotfiles/aws_s3.sh                   "$HOME/aws_s3.sh"
install_file dotfiles/powerlevel10k_lean.omp.json "$HOME/.config/powerlevel10k_lean.omp.json"

# --- Terminal profiles (burib-dark / burib-light, Catppuccin-based) ---
log "Installing Terminal profiles"
mkdir -p "$HOME/.config/terminal-profiles"
cp "$REPO_DIR"/terminal/*.terminal "$HOME/.config/terminal-profiles/"
open "$HOME/.config/terminal-profiles/burib-dark.terminal"
open "$HOME/.config/terminal-profiles/burib-light.terminal"
sleep 2 # give Terminal a moment to register the imported profiles
osascript \
  -e 'tell application "Terminal" to set default settings to settings set "burib-dark"' \
  -e 'tell application "Terminal" to set startup settings to settings set "burib-dark"'

log "Done. Remaining manual steps:"
cat <<'EOF'
  1. Open a new terminal and run `dark` - allow the one-time macOS
     permission prompts (control System Events / Terminal).
  2. gh auth login
  3. aws configure   (credentials are deliberately NOT in this repo)
  4. claude          (sign in on first run)
  5. Close the extra profile-preview Terminal windows.
EOF
