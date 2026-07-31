#!/bin/bash
# Snapshot the CURRENT machine's config back into this repo, so setup_mac.sh
# stays in sync. Run it after changing .zshrc, the Terminal profiles, etc.,
# then review and commit.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cp "$HOME/.zshrc"                              "$REPO_DIR/dotfiles/zshrc"
cp "$HOME/aws_profile.sh"                      "$REPO_DIR/dotfiles/aws_profile.sh"
cp "$HOME/aws_s3.sh"                           "$REPO_DIR/dotfiles/aws_s3.sh"
cp "$HOME/.config/powerlevel10k_lean.omp.json" "$REPO_DIR/dotfiles/powerlevel10k_lean.omp.json"
cp "$HOME"/.config/terminal-profiles/*.terminal "$REPO_DIR/terminal/"

# Dump packages to Brewfile.dump (gitignored) instead of overwriting Brewfile:
# `brew bundle dump` misses some entries (go, oh-my-posh) that were added to
# Brewfile by hand - merge the diff manually when it has something new.
brew bundle dump --force --file "$REPO_DIR/Brewfile.dump"

echo
echo "Captured. Review with: git -C $REPO_DIR diff"
echo "Compare packages with: diff $REPO_DIR/Brewfile $REPO_DIR/Brewfile.dump"
git -C "$REPO_DIR" status --short
