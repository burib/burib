#!/bin/bash
# Snapshot the CURRENT machine's config back into this repo, so setup_mac.sh
# stays in sync. Run it after changing .zshrc, the Terminal profiles, etc.,
# then review and commit.
#
# Only files that exist are copied. The two machines don't have identical sets
# (the work laptop authenticates to AWS differently and has no aws_profile.sh),
# and this script is `set -e`: an unconditional cp of a missing file aborts the
# run half-finished, after earlier files have already been overwritten.
#
# Not captured, deliberately:
#   scripts/dev_utils.sh    - .zshrc sources it from this checkout, so the file
#                             in git IS the live one; there is nothing to copy back
#   ~/.config/zshrc.local   - machine and employer-specific, and this repo is public
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

capture() { # capture <source> <destination-in-repo>
  if [ -e "$1" ]; then
    cp "$1" "$2"
    echo "    captured $1"
  else
    echo "    skipped  $1 (not on this machine)"
  fi
}

capture "$HOME/.zshrc"                              "$REPO_DIR/dotfiles/zshrc"
capture "$HOME/aws_profile.sh"                      "$REPO_DIR/dotfiles/aws_profile.sh"
capture "$HOME/aws_s3.sh"                           "$REPO_DIR/dotfiles/aws_s3.sh"
capture "$HOME/.config/powerlevel10k_lean.omp.json" "$REPO_DIR/dotfiles/powerlevel10k_lean.omp.json"

# Terminal profiles are build output of generate_terminal_profiles.swift. They
# are captured too, so a profile tweaked in Terminal's UI isn't silently lost,
# but prefer editing the palettes in that script and re-running it.
for profile in "$HOME"/.config/terminal-profiles/*.terminal; do
  [ -e "$profile" ] && capture "$profile" "$REPO_DIR/terminal/"
done

# Guard: the overlay must never reach a public repo, however it got there.
if git -C "$REPO_DIR" ls-files --error-unmatch dotfiles/zshrc.local >/dev/null 2>&1; then
  echo "ERROR: dotfiles/zshrc.local is tracked by git - remove it before committing." >&2
  exit 1
fi

# Dump packages to Brewfile.dump (gitignored) instead of overwriting Brewfile:
# `brew bundle dump` misses some entries (go, oh-my-posh) that were added to
# Brewfile by hand - merge the diff manually when it has something new.
brew bundle dump --force --file "$REPO_DIR/Brewfile.dump"

echo
echo "Captured. Review with: git -C $REPO_DIR diff"
echo "Compare packages with: diff $REPO_DIR/Brewfile $REPO_DIR/Brewfile.dump"
git -C "$REPO_DIR" status --short
