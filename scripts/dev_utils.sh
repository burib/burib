#!/bin/zsh
# ~/.config/dev_utils.sh
#
# Utility functions and aliases for development workflows (Git, Terraform, etc.)
# Source this file from your .zshrc:
#   source /path/to/this/file/~/dev_utils.sh

# --- Colors ---
# Real escape characters via $'...', so plain echo works without -e.
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
BLUE=$'\033[0;34m'
BOLD_RED=$'\033[1;31m'
CYAN=$'\033[0;36m'
MAGENTA=$'\033[0;35m'
BOLD=$'\033[1m'
BOLD_BLUE=$'\033[1;34m'
BOLD_WHITE=$'\033[1;37m'
RESET=$'\033[0m'

# --- Git Functions ---

# Get current Git branch and copy to clipboard
function current_branch() {
  local current_branch
  # Try symbolic-ref first, fallback to branch --show-current
  current_branch=$(git symbolic-ref --short HEAD 2>/dev/null || git branch --show-current 2>/dev/null)

  if [[ -z "$current_branch" ]]; then
    echo "${RED}Error: Not on a branch or not in a git repository.${RESET}" >&2
    return 1 # Indicate failure
  fi

  # Clipboard compatibility (macOS vs Linux)
  if command -v pbcopy &> /dev/null; then
    echo "$current_branch" | pbcopy
    echo "${YELLOW}'$current_branch' copied to macOS clipboard.${RESET}"
  elif command -v xclip &> /dev/null; then
    echo "$current_branch" | xclip -selection clipboard
    echo "${YELLOW}'$current_branch' copied to X clipboard.${RESET}"
  elif command -v xsel &> /dev/null; then
    echo "$current_branch" | xsel --clipboard --input
    echo "${YELLOW}'$current_branch' copied to X clipboard.${RESET}"
  else
    echo "${YELLOW}'$current_branch' (clipboard command not found).${RESET}"
  fi
  return 0 # Indicate success
}

# Rebase current branch onto a target branch (default: main)
function rebase_on() {
  local target_branch="${1:-main}" # Default to main if no arg given
  local current_branch

  current_branch=$(git symbolic-ref --short HEAD 2>/dev/null || git branch --show-current 2>/dev/null)

  if [[ -z "$current_branch" ]]; then
    echo "${RED}Error: Could not determine current branch. Not in a git repository?${RESET}" >&2
    return 1
  fi

  if [[ "$current_branch" == "$target_branch" ]]; then
    echo "${YELLOW}Already on '$target_branch'. Pulling...${RESET}"
    git pull || { echo "${RED}Error: Failed to pull '$target_branch'.${RESET}" >&2; return 1; }
    echo "${GREEN}Pull successful on '$target_branch'.${RESET}"
    return 0
  fi

  # Rebase onto origin/<target> directly: no checkout dance, the local target
  # branch is never touched, and --autostash carries uncommitted changes
  # across the rebase (the old checkout-based version refused a dirty tree).
  echo "--> Fetching latest '$target_branch'..."
  git fetch origin "$target_branch" || { echo "${RED}Error: Failed to fetch '$target_branch' from origin.${RESET}" >&2; return 1; }

  echo "--> Rebasing '$current_branch' onto 'origin/$target_branch'..."
  git rebase --autostash "origin/$target_branch" || { echo "${RED}Error: Rebase failed. Please resolve conflicts and run 'git rebase --continue' or 'git rebase --abort'.${RESET}" >&2; return 1; }

  echo "${GREEN}Successfully rebased '$current_branch' onto 'origin/$target_branch'.${RESET}"
  return 0
}

# Checkout main and pull
function main() {
  echo "Switching to main and pulling..."
  git checkout main || { echo "${RED}Error: Failed to checkout main.${RESET}" >&2; return 1; }
  git pull || { echo "${RED}Error: Failed to pull main.${RESET}" >&2; return 1; }
  echo "${GREEN}Switched to main and pulled successfully.${RESET}"
  return 0
}

# Format (in tofu/terraform projects), then commit all tracked changes.
# `commit "msg"` respects hooks; `commit --no-verify "msg"` (= force_commit) bypasses them.
function commit() {
  local no_verify=""
  if [[ "$1" == "--no-verify" ]]; then
    no_verify="--no-verify"
    shift
  fi
  local MESSAGE="$1"
  if [[ -z "$MESSAGE" ]]; then
    echo "${RED}Error: Commit message is required.${RESET}" >&2
    echo "Usage: commit [--no-verify] \"Your commit message\"" >&2
    return 1
  fi

  # (N): null glob, so the array is simply empty when no .tf files exist
  local -a tf_files=( *.tf(N) )
  if (( ${#tf_files} )) || [[ -d .terraform ]]; then
      echo "--> Running ${TF_BIN} fmt --recursive..."
      "$TF_BIN" fmt --recursive
  fi

  echo "--> Committing with message: '$MESSAGE'"
  # -a stages all tracked, modified files; empty $no_verify vanishes in zsh
  git commit -am "$MESSAGE" $no_verify || { echo "${RED}Error: Git commit failed.${RESET}" >&2; return 1; }
  echo "${GREEN}Commit successful.${RESET}"
  return 0
}

# Get Git status
function status() {
  git status
}

# Create a new branch and check it out
function new () {
  local branch_name="$1"
  if [[ -z "$branch_name" ]]; then
    echo "${RED}Error: Branch name is required.${RESET}" >&2
    echo "Usage: new <new-branch-name>" >&2
    return 1
  fi
  git checkout -b "$branch_name" || { echo "${RED}Error: Failed to create branch '$branch_name'. Does it already exist?${RESET}" >&2; return 1; }
  echo "${GREEN}Switched to a new branch '$branch_name'.${RESET}"
  return 0
}

# Delete local branches whose upstream is gone (merged + deleted on the remote)
function prune_gone() {
  git fetch -p || return 1
  local branch deleted=0
  for branch in $(git for-each-ref --format '%(refname:short) %(upstream:track)' refs/heads | awk '$2 == "[gone]" {print $1}'); do
    git branch -D "$branch" && deleted=$((deleted + 1))
  done
  echo "${GREEN}Pruned $deleted stale branch(es).${RESET}"
}

# Open the current branch's PR in the browser, creating it first if none exists
function pr() {
  gh pr view --web 2>/dev/null || gh pr create --fill --web
}

# --- OpenTofu / Terraform ---

# One binary for every alias below: tofu where available, terraform otherwise.
if command -v tofu &> /dev/null; then
  TF_BIN=tofu
elif command -v terraform &> /dev/null; then
  TF_BIN=terraform
else
  TF_BIN=tofu # neither installed (yet) - fail with a name that says what to install
fi

alias init_prod='${TF_BIN} init -backend-config=environments/prod.tfbackend'
alias init_dev='${TF_BIN} init -backend-config=environments/dev.tfbackend'

alias plan='${TF_BIN} plan'
alias plan_dev='echo "\n${BLUE}--- Planning DEV --- ${RESET}\n" && ${TF_BIN} plan -var-file=environments/dev.tfvars'
alias plan_prod='echo "\n${RED}--- Planning PROD --- ${RESET}\n" && ${TF_BIN} plan -var-file=environments/prod.tfvars'
alias plan_prod_remote='echo "\n${RED}--- Planning PROD (remote state default vars) --- ${RESET}\n" && ${TF_BIN} plan'

# Policy: dev applies auto-approve, prod ALWAYS prompts - the confirmation
# step is the point on prod.
alias apply='${TF_BIN} apply'
alias apply_dev='echo "\n${BLUE}--- Applying DEV --- ${RESET}\n" && ${TF_BIN} apply -var-file=environments/dev.tfvars --auto-approve'
alias apply_prod='echo "\n${RED}*** Applying PROD - review the plan before typing yes ***${RESET}\n" && ${TF_BIN} apply -var-file=environments/prod.tfvars'
alias apply_prod_remote='echo "\n${RED}*** Applying PROD (remote state default vars) - review the plan ***${RESET}\n" && ${TF_BIN} apply'

alias destroy_dev='echo "\n${BOLD_RED}*** DESTROYING DEV ***${RESET}\n" && ${TF_BIN} destroy -var-file=environments/dev.tfvars'

alias fmt='${TF_BIN} fmt --recursive'

function unlock() {
  local LOCK_ID="$1"
  if [[ -z "$LOCK_ID" ]]; then
     echo "${RED}Error: Lock ID is required.${RESET}" >&2
     echo "Usage: unlock <LOCK_ID>" >&2
     echo "Hint: a locked plan/apply prints the Lock ID it is blocked on." >&2
     return 1
  fi
  echo "${YELLOW}Attempting to force-unlock Lock ID: $LOCK_ID${RESET}"
  "$TF_BIN" force-unlock -force "$LOCK_ID"
}

# --- General Aliases ---

alias branch="current_branch"
alias rebase="rebase_on main" # Default rebase points to main
alias rebase_main="rebase_on main"
alias rebase_master="rebase_on master"
alias force_commit='echo "${YELLOW}Bypassing pre-commit hooks (--no-verify)${RESET}" && commit --no-verify'

alias pull="git pull"
alias push="git push"

alias check="pre-commit run -a" # Assumes pre-commit is installed

# --- Text Utilities ---

function lowerCase() {
  tr '[:upper:]' '[:lower:]'
}

function upperCase() {
  tr '[:lower:]' '[:upper:]'
}

# Converts input lines to Sentence Case (first letter upper, rest lower).
# Pure zsh: `read` into a single var already trims surrounding whitespace,
# and the (U)/(L) expansion flags replace the tr/sed subshells.
function sentenceCase() {
    local line
    while read -r line; do
        print -r -- "${(U)line[1]}${(L)line[2,-1]}"
    done
}

# Converts input lines to Title Case (first letter of each word capitalized) using Zsh parameter expansion
titleCase() {
    # Read input from stdin
    while read -r line; do
        # Use Zsh's parameter expansion flags: ${(C)name} capitalizes each word
        print -r -- "${(C)line}"
    done
}

# Make a directory (parents included) and cd into it
function mkcd() {
  mkdir -p "$1" && cd "$1"
}

# Generate a lowercase UUID
uuid() {
  # Check if uuidgen exists
  if command -v uuidgen &> /dev/null; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  else
    echo "${RED}Error: 'uuidgen' command not found.${RESET}" >&2
    return 1
  fi
}


# --- GitHub Org Utilities ---

# Clone or update all non-archived repositories from a GitHub organization
function clone_all_org_repos() {
  # Check for required tools
  if ! command -v gh &> /dev/null; then echo "Error: GitHub CLI 'gh' not found." >&2; return 1; fi
  if ! command -v git &> /dev/null; then echo "Error: 'git' not found." >&2; return 1; fi

  # Check gh authentication status
  if ! gh auth status &> /dev/null; then echo "Error: Not logged into GitHub CLI. Run 'gh auth login'." >&2; return 1; fi

  # --- Arguments ---
  local org_name="$1"
  # Default target directory: ./<org_name>_repos
  local target_dir="${2:-./${org_name}_repos}"

  if [[ -z "$org_name" ]]; then
    echo "Usage: clone_all_org_repos <org_name> [target_directory]" >&2
    echo "Example: clone_all_org_repos my-github-org ~/dev/my-github-org" >&2
    return 1
  fi

  echo "Fetching repository list for organization: '$org_name'..."

  # --- Fetch Repo List ---
  local repo_id_list # Store the clean list of owner/repo
  # Increased limit just in case, adjust if needed
  if ! repo_id_list=$(gh repo list "$org_name" --limit 5000 --no-archived --json nameWithOwner -q '.[].nameWithOwner'); then
      echo "${RED}Error: Failed to fetch repository list using 'gh repo list'. Check org name and permissions.${RESET}" >&2
      return 1
  fi

  if [[ -z "$repo_id_list" ]]; then
      echo "${YELLOW}No non-archived repositories found for organization '$org_name' or you may lack permissions.${RESET}"
      return 0
  fi

  echo "Target directory: '$target_dir'"
  mkdir -p "$target_dir" || { echo "${RED}Error: Failed to create target directory '$target_dir'.${RESET}" >&2; return 1; }

  # --- Process Repositories ---
  local repo_id repo_name clone_path
  local success_count=0 update_count=0 fail_count=0 skip_count=0
  local total_count=$(echo "$repo_id_list" | wc -l | tr -d ' ') # Count lines for total

  echo "Processing $total_count repositories..."

  # Use process substitution for cleaner loop reading
  while IFS= read -r repo_id; do
    # Skip empty lines just in case
    if [[ -z "$repo_id" ]]; then continue; fi

    repo_name=$(basename "$repo_id") # Extract repo name (e.g., my-repo) from OWNER/REPO
    clone_path="$target_dir/$repo_name" # Construct full path for clone/pull

    echo # Add a newline for better readability between repos
    echo "Processing '$repo_name' (from $repo_id)..."

    # Check if directory already exists and is a git repo
    if [[ -d "$clone_path/.git" ]]; then
      echo " -> Directory exists. Updating (git pull --rebase)..."
      # Use -C to change directory for the git command only
      # Pull with rebase to avoid merge commits, add --ff-only if preferred
      if git -C "$clone_path" pull --rebase; then
        echo " ${GREEN}-> Update successful for '$repo_name'.${RESET}"
        update_count=$((update_count + 1))
      else
        echo " ${RED}Error: Failed to update '$repo_name'. Check for conflicts or errors above.${RESET}" >&2
        fail_count=$((fail_count + 1))
      fi
    elif [[ -e "$clone_path" ]]; then
       # Path exists but is not a git repository or a broken symlink etc.
       echo " ${YELLOW}Warning: Path '$clone_path' exists but is not a git repository. Skipping '$repo_name'.${RESET}" >&2
       skip_count=$((skip_count + 1))
    else
      # Directory does not exist, clone it using gh repo clone
      echo " -> Cloning '$repo_id' into '$clone_path'..."
      # gh repo clone OWNER/REPO TARGET_DIRECTORY
      if gh repo clone "$repo_id" "$clone_path"; then
        echo " ${GREEN}-> Clone successful for '$repo_name'.${RESET}"
        success_count=$((success_count + 1))
      else
        echo " ${RED}Error: Failed to clone '$repo_name' using 'gh repo clone'.${RESET}" >&2
        fail_count=$((fail_count + 1))
      fi
    fi
  done <<< "$repo_id_list" # Feed the clean repo ID list into the loop

  # --- Summary ---
  echo "\n----- Clone/Update Summary -----"
  echo "Total repositories found:   $total_count"
  echo "Successfully cloned:        $success_count"
  echo "Successfully updated:       $update_count"
  echo "Skipped (path exists):      $skip_count"
  echo "Failed operations:          $fail_count"
  echo "------------------------------"

  if [[ $fail_count -gt 0 ]]; then
      echo "${RED}Some operations failed. Please review the output above.${RESET}"
      return 1 # Return error code if any operation failed
  fi
  return 0
}

# Optional: Add an alias for convenience
alias clone_org=clone_all_org_repos


# --- AWS / DNS / misc helpers ---
# These lived only on the work laptop until now. Nothing in here is
# employer-specific: `me` reads whatever account you are authenticated to,
# and aws_edge_security audits whatever regions you point it at. Anything
# tied to a specific account or registry belongs in ~/.config/zshrc.local.

# Function to convert a PDF file to a PNG image (first page only using sips)
# Usage: pdf2png input.pdf
# Output: input.png (in the same directory as the input PDF)
pdf2png() {
  # Ensure at least one argument is provided
  if [ $# -eq 0 ]; then
    echo "Usage: pdf2png <input.pdf_file>"
    echo "Creates <input.png> from the first page of <input.pdf_file>."
    return 1
  fi

  local input_pdf="$1"
  local output_png

  # Check if input_pdf actually exists and is a file
  if [ ! -f "$input_pdf" ]; then
    echo "Error: Input file '$input_pdf' not found."
    return 1
  fi

  # Use Zsh's parameter expansion to get the file extension and base name
  # :e gets the extension, :r gets the root name (path/to/file without extension)
  local extension="${input_pdf:e}"
  local basename="${input_pdf:r}"

  # Check if the extension is 'pdf' (case-insensitive using :l for lowercase)
  if [[ "${extension:l}" != "pdf" ]]; then
    echo "Error: Input file '$input_pdf' does not appear to be a PDF."
    echo "Expected .pdf extension, got .$extension"
    return 1
  fi

  # Define the output filename (e.g., example.pdf -> example.png)
  output_png="${basename}.png"

  # Perform the conversion using sips
  # sips will overwrite output_png if it already exists without warning.
  # sips typically converts only the first page of a multi-page PDF to the output file.
  echo "Converting '$input_pdf' to '$output_png'..."

  # sips can be verbose; redirect its normal output to /dev/null.
  # We'll check its exit status and the presence of the output file.
  if sips -s format png "$input_pdf" --out "$output_png" >/dev/null 2>&1; then
    # Check if output file was actually created and is not empty
    if [ -s "$output_png" ]; then
      echo "Successfully created '$output_png'"
    else
      echo "Error: Conversion seemed to succeed (sips exit code 0), but '$output_png' was not created or is empty."
      echo "The PDF might be corrupted or unsupported by sips for conversion."
      # Attempt to remove a potentially empty/failed output.
      [ -f "$output_png" ] && rm "$output_png"
      return 1
    fi
  else
    echo "Error: sips command failed to convert '$input_pdf'."
    # sips might have printed an error message to stderr if not fully redirected,
    # or simply exited with a non-zero status.
    return 1
  fi
}

# Display current AWS identity, region, account alias, and more in a table
me() {
  if ! command -v aws &> /dev/null; then
    echo "${RED}Error: AWS CLI 'aws' not found.${RESET}" >&2
    return 1
  fi

  local caller_identity
  if ! caller_identity=$(aws sts get-caller-identity --output json 2>&1); then
    echo "${RED}Error: Failed to get caller identity. Are you authenticated?${RESET}" >&2
    echo "$caller_identity" >&2
    return 1
  fi

  local account arn user_id
  account=$(echo "$caller_identity" | grep -o '"Account": *"[^"]*"' | cut -d'"' -f4)
  arn=$(echo "$caller_identity" | grep -o '"Arn": *"[^"]*"' | cut -d'"' -f4)
  user_id=$(echo "$caller_identity" | grep -o '"UserId": *"[^"]*"' | cut -d'"' -f4)

  local region="${AWS_DEFAULT_REGION:-${AWS_REGION:-$(aws configure get region 2>/dev/null || echo "not set")}}"
  local profile="${AWS_PROFILE:-default}"
  local account_aliases
  account_aliases=$(aws iam list-account-aliases --query 'AccountAliases' --output text 2>/dev/null || echo "n/a")
  if [[ -z "$account_aliases" ]]; then account_aliases="n/a"; fi

  # Extract a friendly name from the ARN
  local identity_type="unknown"
  case "$arn" in
    *:assumed-role/*)  identity_type="Assumed Role: ${arn##*:assumed-role/}" ;;
    *:user/*)          identity_type="IAM User: ${arn##*:user/}" ;;
    *:root)            identity_type="Root Account" ;;
    *:federated-user/*) identity_type="Federated User: ${arn##*:federated-user/}" ;;
    *)                 identity_type="$arn" ;;
  esac

  # --- Session Expiration ---
  local expiration=""

  # Helper: parse ISO 8601 timestamp to epoch seconds
  _parse_iso_epoch() {
    local ts="$1"
    if command -v gdate &> /dev/null; then
      gdate -d "$ts" +%s 2>/dev/null
    else
      TZ=UTC date -jf "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null \
        || TZ=UTC date -jf "%Y-%m-%dT%H:%M:%SUTC" "$ts" +%s 2>/dev/null \
        || TZ=UTC date -jf "%Y-%m-%dT%H:%M:%S" "$ts" +%s 2>/dev/null \
        || date -jf "%Y-%m-%dT%H:%M:%S%z" "$ts" +%s 2>/dev/null
    fi
  }

  local now_epoch
  now_epoch=$(date +%s)

  # 1. Check AWS_CREDENTIAL_EXPIRATION env var (set by some credential providers)
  if [[ -n "$AWS_CREDENTIAL_EXPIRATION" ]]; then
    expiration="$AWS_CREDENTIAL_EXPIRATION"
  fi

  # 2. Try 'aws configure export-credentials' (works with all credential sources)
  if [[ -z "$expiration" ]]; then
    local exported_exp
    exported_exp=$(aws configure export-credentials --format process 2>/dev/null \
      | grep -o '"Expiration": *"[^"]*"' | head -1 | cut -d'"' -f4)
    if [[ -n "$exported_exp" ]]; then
      expiration="$exported_exp"
    fi
  fi

  # 3. Check CLI credential cache files (~/.aws/cli/cache/*.json)
  #    Only use entries whose Expiration is in the future (skip stale files)
  if [[ -z "$expiration" ]] && [[ -d "$HOME/.aws/cli/cache" ]]; then
    local cache_file exp_candidate cand_epoch
    for cache_file in "$HOME"/.aws/cli/cache/*.json(N); do
      exp_candidate=$(grep -o '"Expiration": *"[^"]*"' "$cache_file" 2>/dev/null | head -1 | cut -d'"' -f4)
      if [[ -n "$exp_candidate" ]]; then
        cand_epoch=$(_parse_iso_epoch "$exp_candidate")
        # Only consider if expiration is in the future
        if [[ -n "$cand_epoch" && "$cand_epoch" -gt "$now_epoch" ]]; then
          if [[ -z "$expiration" || "$exp_candidate" > "$expiration" ]]; then
            expiration="$exp_candidate"
          fi
        fi
      fi
    done
  fi

  # 4. Check SSO cache files (~/.aws/sso/cache/*.json)
  #    Only use accessToken entries (have "accessToken" key) with future expiresAt
  if [[ -z "$expiration" ]] && [[ -d "$HOME/.aws/sso/cache" ]]; then
    local cache_file exp_candidate cand_epoch
    for cache_file in "$HOME"/.aws/sso/cache/*.json(N); do
      # Skip client registration files (they have clientId but no accessToken)
      grep -q '"accessToken"' "$cache_file" 2>/dev/null || continue
      exp_candidate=$(grep -o '"expiresAt": *"[^"]*"' "$cache_file" 2>/dev/null | head -1 | cut -d'"' -f4)
      if [[ -n "$exp_candidate" ]]; then
        cand_epoch=$(_parse_iso_epoch "$exp_candidate")
        if [[ -n "$cand_epoch" && "$cand_epoch" -gt "$now_epoch" ]]; then
          if [[ -z "$expiration" || "$exp_candidate" > "$expiration" ]]; then
            expiration="$exp_candidate"
          fi
        fi
      fi
    done
  fi

  # Calculate display values
  local expires_display="n/a"
  local minutes_left_display=""
  if [[ -n "$expiration" ]]; then
    expires_display="$expiration"
    local exp_epoch
    exp_epoch=$(_parse_iso_epoch "$expiration")

    if [[ -n "$exp_epoch" ]]; then
      local local_time utc_time
      if command -v gdate &> /dev/null; then
        local_time=$(gdate -d "@$exp_epoch" +"%Y-%m-%d %H:%M" 2>/dev/null)
        utc_time=$(TZ=UTC gdate -d "@$exp_epoch" +"%H:%M" 2>/dev/null)
      else
        local_time=$(date -r "$exp_epoch" +"%Y-%m-%d %H:%M" 2>/dev/null)
        utc_time=$(TZ=UTC date -r "$exp_epoch" +"%H:%M" 2>/dev/null)
      fi
      if [[ -n "$local_time" && -n "$utc_time" ]]; then
        expires_display="${local_time} local (${utc_time} UTC)"
      fi

      local diff_seconds=$((exp_epoch - now_epoch))
      local diff_minutes=$((diff_seconds / 60))

      if [[ $diff_seconds -le 0 ]]; then
        minutes_left_display="${RED}EXPIRED${RESET}"
      elif [[ $diff_minutes -lt 15 ]]; then
        minutes_left_display="${RED}${diff_minutes} min remaining${RESET}"
      elif [[ $diff_minutes -lt 60 ]]; then
        minutes_left_display="${YELLOW}${diff_minutes} min remaining${RESET}"
      else
        local hours=$((diff_minutes / 60))
        local remaining_min=$((diff_minutes % 60))
        minutes_left_display="${GREEN}${hours}h ${remaining_min}m remaining${RESET}"
      fi
    fi
  fi

  unfunction _parse_iso_epoch 2>/dev/null

  local sep="+-----------------------+--------------------------------------------------------------+"
  local fmt="| ${YELLOW}%-21s${RESET} | %-60s |"
  local fmt_color="| ${YELLOW}%-21s${RESET} | %-49b |"

  echo ""
  echo "$sep"
  printf "$fmt\n" "AWS Profile"       "$profile"
  echo "$sep"
  printf "$fmt\n" "Identity"          "$identity_type"
  printf "$fmt\n" "Account ID"        "$account"
  printf "$fmt\n" "Account Alias"     "$account_aliases"
  printf "$fmt\n" "Region"            "$region"
  printf "$fmt\n" "User ID"           "$user_id"
  printf "$fmt\n" "ARN"               "$arn"
  echo "$sep"
  printf "$fmt\n" "Session Expires"   "$expires_display"
  if [[ -n "$minutes_left_display" ]]; then
    printf "$fmt_color\n" "Time Remaining"    "$minutes_left_display"
  else
    printf "$fmt\n" "Time Remaining"    "n/a"
  fi
  echo "$sep"
  echo ""
}

# Audit public-facing edge resources for WAF and Shield Advanced coverage.
# Global pass : CloudFront distributions, Global Accelerator accelerators.
# Per-region  : internet-facing Application, Network and Classic Load Balancers,
#               API Gateway REST API stages, Elastic IPs.
# For each resource it reports whether a WAFv2 Web ACL is associated (and lists
# its rules) and whether the resource is protected by Shield Advanced.
#
# WAF can only attach to CloudFront, ALBs and API Gateway. Network and Classic
# Load Balancers, Global Accelerator and Elastic IPs support Shield Advanced
# only, so WAF is shown as n/a for them. Only internet-facing load balancers are
# scanned; internal ones are not internet-reachable (and cannot take Shield
# Advanced), so they are out of scope.
#
# Requires: aws (v2), jq. Needs IAM permissions for cloudfront:List*,
# elasticloadbalancing:Describe*, apigateway:GET, wafv2:Get*, shield:List*/Get*,
# globalaccelerator:List*, ec2:DescribeRegions, ec2:DescribeAddresses,
# ec2:DescribeNetworkInterfaces, sts:GetCallerIdentity, iam:ListAccountAliases.
# The Organizations account name
# additionally needs organizations:DescribeAccount (management / delegated-admin
# account only); it is skipped silently when unavailable.
#
# Usage:
#   aws_edge_security                    # global pass + all enabled regions
#   aws_edge_security eu-central-1       # global pass + only the given region(s)
#   aws_edge_security eu-central-1 eu-west-1
#   aws_edge_security --no-cloudfront eu-central-1   # skip the CloudFront pass
#
# Notes:
#   - The global pass (CloudFront + Global Accelerator) always runs regardless
#     of which regions are passed; CloudFront can be skipped with --no-cloudfront.
#   - WAF Classic (WAFv1) associations show up as "WAF Classic" without rules.
#   - Network/Classic LBs and HTTP (v2) APIs cannot use WAF (Shield-only). HTTP
#     (v2) APIs are not scanned; internet-facing NLBs are (Shield only).
#   - Shield Advanced lookups require an active subscription; without one, the
#     Shield column simply reports "no subscription".
#   - A PROTECTED resource may show "(no health check)" (no associated Route 53
#     health check for health-based detection); recommended-but-optional, not a
#     hard failure. L7 DDoS mitigation is reported separately: the Anti-DDoS
#     managed rule group is marked "← L7 DDoS mitigation" in the Web ACL rule
#     list. The Shield "automatic application-layer response" (ALAR) is not
#     checked, as AWS is retiring it in favour of that rule group.
aws_edge_security() {
  # Dependency check
  local dep
  for dep in aws jq; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      echo "${RED}Error: '$dep' is required but not installed.${RESET}" >&2
      return 1
    fi
  done

  # Parse flags and region arguments.
  local scan_cloudfront=1
  local -a region_args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        echo "Usage: aws_edge_security [--no-cloudfront] [region ...]"
        echo ""
        echo "Audits public-facing edge resources for WAFv2 and Shield Advanced coverage:"
        echo "  Global : CloudFront distributions, Global Accelerator accelerators"
        echo "  Region : internet-facing ALBs, Classic LBs, API Gateway REST stages, EIPs"
        echo ""
        echo "WAF applies only to CloudFront, ALBs and API Gateway; CLBs, Global"
        echo "Accelerator and EIPs support Shield Advanced only (WAF shown as n/a)."
        echo ""
        echo "Options:"
        echo "  --no-cloudfront   skip the CloudFront pass (Global Accelerator still runs)"
        echo "  region ...        regions to scan (default: all enabled regions)"
        return 0
        ;;
      --no-cloudfront|--no-cf)
        scan_cloudfront=0
        ;;
      -*)
        echo "${RED}Error: unknown option '$1' (see --help).${RESET}" >&2
        return 1
        ;;
      *)
        region_args+=("$1")
        ;;
    esac
    shift
  done

  # Verify credentials early and grab the account id (needed to build ARNs).
  local account_id
  account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
  if [[ -z "$account_id" || "$account_id" == "None" ]]; then
    echo "${RED}Error: unable to determine AWS identity. Are your credentials valid?${RESET}" >&2
    return 1
  fi

  # Account alias (from IAM; blank if none set) and Organizations account name
  # (only resolvable with organizations:DescribeAccount, i.e. from the
  # management or a delegated-admin account; silently skipped otherwise).
  local account_alias account_name
  account_alias=$(aws iam list-account-aliases --query 'AccountAliases[0]' --output text 2>/dev/null)
  [[ "$account_alias" == "None" ]] && account_alias=""
  account_name=$(aws organizations describe-account --account-id "$account_id" \
    --query 'Account.Name' --output text 2>/dev/null)
  [[ "$account_name" == "None" ]] && account_name=""

  local account_label="$account_id"
  [[ -n "$account_name" ]]  && account_label="$account_label  name=\"$account_name\""
  [[ -n "$account_alias" ]] && account_label="$account_label  alias=\"$account_alias\""
  echo "${CYAN}▶ AWS account: $account_label${RESET}"

  # --- Preload Shield Advanced protections (global, one call). The Protection
  #     objects already carry the per-resource detail we need (automatic
  #     application-layer response + associated health checks), so no extra
  #     describe-protection calls are required. ---
  local shield_state shield_json="" shield_arns=""
  shield_state=$(aws shield get-subscription-state --query SubscriptionState --output text 2>/dev/null)
  if [[ "$shield_state" == "ACTIVE" ]]; then
    echo "${GREEN}▶ Shield Advanced: subscription ACTIVE${RESET}"
    shield_json=$(aws shield list-protections --output json 2>/dev/null)
    shield_arns=$(echo "$shield_json" | jq -r '.Protections[]?.ResourceArn' 2>/dev/null)
  else
    echo "${YELLOW}▶ Shield Advanced: no active subscription (Shield column = standard only)${RESET}"
  fi

  # Report Shield Advanced posture for a resource ARN:
  #   "no subscription" / "standard only" / "PROTECTED" (+ gap annotation).
  # For PROTECTED resources it flags a missing associated Route 53 health check
  # (health-based detection, recommended for any protected resource).
  #
  # It deliberately does NOT flag the Shield "automatic application-layer
  # response" (ALAR): AWS is retiring that feature (the WAF Anti-DDoS managed
  # rule group became the default on 2026-03-26 and new accounts can no longer
  # enable ALAR). L7 DDoS mitigation now lives in the Web ACL via
  # AWSManagedRulesAntiDDoSRuleSet, which _print_webacl marks in the rule list.
  _shield_status() {
    local arn="$1"
    if [[ "$shield_state" != "ACTIVE" ]]; then
      echo "no subscription"; return
    fi
    if ! echo "$shield_arns" | grep -qxF "$arn"; then
      echo "${YELLOW}standard only${RESET}"; return
    fi
    # Protected: flag only a missing associated health check.
    local hc extra=""
    hc=$(echo "$shield_json" | jq -r --arg arn "$arn" '
      .Protections[]? | select(.ResourceArn == $arn)
      | ((.HealthCheckIds // []) | length)' 2>/dev/null | head -1)
    if [[ -z "$hc" || "$hc" == "0" ]]; then
      extra=" ${YELLOW}(no health check)${RESET}"
    fi
    echo "${GREEN}PROTECTED${RESET}$extra"
  }

  # Prints the rules of a Web ACL JSON blob (the object under .WebACL), reading
  # JSON from stdin. Rate-based limits are grouped with thousands separators and
  # converted to an approximate requests/second figure (limit / eval window;
  # the window defaults to 300s / 5min when WAF does not report one).
  _print_webacl() {
    jq -r '
      # Group an integer with thousands separators (e.g. 400000 -> "400,000").
      def commafy:
        tostring
        | . as $n
        | reduce range(0; ($n|length)) as $i
            ("";
             . + $n[$i:$i+1]
             + (if ((($n|length) - $i - 1) % 3 == 0) and ($i != (($n|length) - 1))
                then "," else "" end));
      .WebACL as $w
      | "      default action: \($w.DefaultAction | keys[0])"
      , ( $w.Rules // []
          | if length == 0 then "      (no rules)"
            else ( .[]
              | .Statement as $s
              | "        [\(.Priority)] \(.Name)"
                + ( if $s.ManagedRuleGroupStatement
                      then "  managed: \($s.ManagedRuleGroupStatement.VendorName)/\($s.ManagedRuleGroupStatement.Name)"
                         + ( if $s.ManagedRuleGroupStatement.Name == "AWSManagedRulesAntiDDoSRuleSet"
                             then "  ← L7 DDoS mitigation" else "" end )
                    elif $s.RateBasedStatement
                      then ($s.RateBasedStatement.Limit) as $lim
                         | (($s.RateBasedStatement.EvaluationWindowSec) // 300) as $win
                         | "  rate-based: \($lim|commafy) req / \($win)s window ≈ \((($lim / $win) | floor) | commafy) rps"
                    elif $s.IPSetReferenceStatement then "  ip-set"
                    else "" end ) )
            end )
    ' 2>/dev/null
  }

  # Print one concise status line for a resource, plus WAF rules if associated.
  # Args: <display> <resource-arn> <region> <waf_capable: 1|0>
  _audit_resource() {
    local display="$1" arn="$2" region="$3" waf_capable="$4"
    local shield; shield=$(_shield_status "$arn")
    if [[ "$waf_capable" != "1" ]]; then
      echo "    ${BOLD}$display${RESET}  Shield: $shield"
      return
    fi
    local acl; acl=$(aws wafv2 get-web-acl-for-resource --resource-arn "$arn" --region "$region" 2>/dev/null)
    if [[ -n "$acl" ]] && echo "$acl" | jq -e '.WebACL' >/dev/null 2>&1; then
      local wname; wname=$(echo "$acl" | jq -r '.WebACL.Name')
      echo "    ${BOLD}$display${RESET}  WAF: ${GREEN}$wname${RESET}  Shield: $shield"
      echo "$acl" | _print_webacl
    else
      echo "    ${BOLD}$display${RESET}  WAF: ${RED}NONE${RESET}  Shield: $shield"
    fi
  }

  # Determine which regions to scan.
  local regions
  if [[ ${#region_args[@]} -gt 0 ]]; then
    regions="${region_args[*]}"
  else
    regions=$(aws ec2 describe-regions --query 'Regions[].RegionName' --output text 2>/dev/null)
    if [[ -z "$regions" ]]; then
      regions=$(aws configure get region 2>/dev/null)
    fi
    if [[ -z "$regions" ]]; then
      echo "${RED}Error: could not determine regions to scan. Pass region(s) explicitly.${RESET}" >&2
      return 1
    fi
  fi

  echo ""

  # ============================ CloudFront (global) ============================
  # Parse via jq (not --query text): an empty distribution list must yield no
  # rows, otherwise --output text emits a spurious "None" line.
  if [[ "$scan_cloudfront" -eq 1 ]]; then
    local cf_items
    cf_items=$(aws cloudfront list-distributions --output json 2>/dev/null \
      | jq -r '.DistributionList.Items // [] | .[] | [.Id, .DomainName, (.WebACLId // "")] | @tsv' 2>/dev/null)
    if [[ -z "$cf_items" ]]; then
      echo "${BOLD_BLUE}▷ CloudFront (global):${RESET} none"
    else
      echo "${BOLD_BLUE}▷ CloudFront (global):${RESET}"
      echo "$cf_items" | while IFS=$'\t' read -r cf_id cf_domain cf_webacl; do
        [[ -z "$cf_id" ]] && continue
        local cf_arn="arn:aws:cloudfront::${account_id}:distribution/${cf_id}"
        local shield="$(_shield_status "$cf_arn")"
        if [[ -z "$cf_webacl" ]]; then
          echo "    ${BOLD}$cf_id${RESET} ($cf_domain)  WAF: ${RED}NONE${RESET}  Shield: $shield"
        elif [[ "$cf_webacl" == arn:aws:wafv2:* ]]; then
          local wname="$(echo "$cf_webacl" | awk -F/ '{print $(NF-1)}')"
          local wid="$(echo "$cf_webacl" | awk -F/ '{print $NF}')"
          echo "    ${BOLD}$cf_id${RESET} ($cf_domain)  WAF: ${GREEN}$wname${RESET}  Shield: $shield"
          aws wafv2 get-web-acl --scope CLOUDFRONT --region us-east-1 \
            --name "$wname" --id "$wid" 2>/dev/null | _print_webacl
        else
          echo "    ${BOLD}$cf_id${RESET} ($cf_domain)  WAF: ${YELLOW}Classic(v1)${RESET}  Shield: $shield"
        fi
      done
    fi
  fi

  # ========================= Global Accelerator (global) =======================
  # Global Accelerator is a global service reached via the us-west-2 endpoint.
  # It supports Shield Advanced only (no WAF).
  local ga_list
  ga_list=$(aws globalaccelerator list-accelerators --region us-west-2 \
    --query 'Accelerators[].[AcceleratorArn,Name,Enabled]' --output text 2>/dev/null)
  if [[ -z "$ga_list" ]]; then
    echo "${BOLD_BLUE}▷ Global Accelerator (global):${RESET} none"
  else
    echo "${BOLD_BLUE}▷ Global Accelerator (global):${RESET}"
    echo "$ga_list" | while IFS=$'\t' read -r ga_arn ga_name ga_enabled; do
      [[ -z "$ga_arn" ]] && continue
      _audit_resource "$ga_name (enabled=$ga_enabled)" "$ga_arn" us-west-2 0
    done
  fi

  # ============================ Per-region resources ===========================
  local region
  for region in ${=regions}; do
    echo ""
    echo "${BOLD_BLUE}=== Region: $region ===${RESET}"

    # ---- Internet-facing Application Load Balancers ----
    local albs
    albs=$(aws elbv2 describe-load-balancers --region "$region" \
      --query "LoadBalancers[?Type=='application' && Scheme=='internet-facing'].[LoadBalancerArn,DNSName]" \
      --output text 2>/dev/null)
    if [[ -z "$albs" ]]; then
      echo "${CYAN}  ALBs (internet-facing):${RESET} none"
    else
      echo "${CYAN}  ALBs (internet-facing):${RESET}"
      echo "$albs" | while IFS=$'\t' read -r alb_arn alb_dns; do
        [[ -z "$alb_arn" ]] && continue
        _audit_resource "$alb_dns" "$alb_arn" "$region" 1
      done
    fi

    # ---- Internet-facing Network Load Balancers (WAF n/a, Shield only) ----
    local nlbs
    nlbs=$(aws elbv2 describe-load-balancers --region "$region" \
      --query "LoadBalancers[?Type=='network' && Scheme=='internet-facing'].[LoadBalancerArn,DNSName]" \
      --output text 2>/dev/null)
    if [[ -z "$nlbs" ]]; then
      echo "${CYAN}  NLBs (internet-facing):${RESET} none"
    else
      echo "${CYAN}  NLBs (internet-facing):${RESET}"
      echo "$nlbs" | while IFS=$'\t' read -r nlb_arn nlb_dns; do
        [[ -z "$nlb_arn" ]] && continue
        _audit_resource "$nlb_dns" "$nlb_arn" "$region" 0
      done
    fi

    # ---- Internet-facing Classic Load Balancers (WAF n/a, Shield only) ----
    local clbs
    clbs=$(aws elb describe-load-balancers --region "$region" \
      --query "LoadBalancerDescriptions[?Scheme=='internet-facing'].[LoadBalancerName,DNSName]" \
      --output text 2>/dev/null)
    if [[ -z "$clbs" ]]; then
      echo "${CYAN}  Classic LBs (internet-facing):${RESET} none"
    else
      echo "${CYAN}  Classic LBs (internet-facing):${RESET}"
      echo "$clbs" | while IFS=$'\t' read -r clb_name clb_dns; do
        [[ -z "$clb_name" ]] && continue
        local clb_arn="arn:aws:elasticloadbalancing:${region}:${account_id}:loadbalancer/${clb_name}"
        _audit_resource "$clb_name ($clb_dns)" "$clb_arn" "$region" 0
      done
    fi

    # ---- Elastic IPs (WAF n/a, Shield only). Resolve what each EIP fronts by
    #      inspecting its network interface (InterfaceType / Description reveal
    #      the creator: NAT gateway, load balancer, instance, etc.), then flag
    #      only the ones that are genuine inbound entry points left off Shield
    #      Advanced. NAT gateways (egress) and load-balancer ENIs (Shield is
    #      registered on the LB, not the EIP) are not gaps and are not flagged.
    local eips
    eips=$(aws ec2 describe-addresses --region "$region" \
      --query 'Addresses[].[PublicIp,AllocationId,InstanceId,NetworkInterfaceId]' \
      --output text 2>/dev/null)
    if [[ -z "$eips" ]]; then
      echo "${CYAN}  Elastic IPs:${RESET} none"
    else
      echo "${CYAN}  Elastic IPs:${RESET}"
      echo "$eips" | while IFS=$'\t' read -r eip_ip eip_alloc eip_instance eip_eni; do
        [[ -z "$eip_ip" ]] && continue
        local eip_arn="arn:aws:ec2:${region}:${account_id}:eip-allocation/${eip_alloc}"
        local sh="$(_shield_status "$eip_arn")"
        local attach="" inbound=0
        if [[ -n "$eip_eni" && "$eip_eni" != "None" ]]; then
          # Describe the ENI to learn the interface type + description (creator).
          local eni_info="$(aws ec2 describe-network-interfaces --region "$region" \
            --network-interface-ids "$eip_eni" \
            --query 'NetworkInterfaces[0].[InterfaceType,Description,RequesterId]' \
            --output text 2>/dev/null)"
          local eni_type="$(echo "$eni_info" | cut -f1)"
          local eni_desc="$(echo "$eni_info" | cut -f2)"
          local eni_req="$(echo "$eni_info" | cut -f3)"
          [[ "$eni_desc" == "None" || -z "$eni_desc" ]] && eni_desc="$eip_eni"
          if [[ "$eni_type" == "nat_gateway" ]]; then
            attach="→ ${eni_type}: ${eni_desc}"                     # egress only
          elif [[ "$eni_desc" == ELB\ * || "$eni_req" == *elb* ]]; then
            attach="→ ${eni_desc} (Shield applies at the load balancer)"
          elif [[ -n "$eip_instance" && "$eip_instance" != "None" ]]; then
            attach="→ instance ${eip_instance} (${eni_desc})"; inbound=1
          else
            attach="→ ${eni_type}: ${eni_desc}"; inbound=1
          fi
        elif [[ -n "$eip_instance" && "$eip_instance" != "None" ]]; then
          attach="→ instance ${eip_instance}"; inbound=1
        else
          attach="${YELLOW}UNATTACHED${RESET}"
        fi
        # Flag genuine inbound entry points that are not under Shield Advanced.
        local flag=""
        if [[ "$inbound" -eq 1 && "$sh" != *PROTECTED* ]]; then
          flag="  ${BOLD_RED}⚠ inbound EIP not under Shield Advanced${RESET}"
        fi
        echo "    ${BOLD}$eip_ip${RESET} ($eip_alloc) $attach  Shield: $sh$flag"
      done
    fi

    # ---- API Gateway REST API stages ----
    local apis
    apis=$(aws apigateway get-rest-apis --region "$region" \
      --query 'items[].[id,name]' --output text 2>/dev/null)
    if [[ -z "$apis" ]]; then
      echo "${CYAN}  API Gateway REST stages:${RESET} none"
    else
      echo "${CYAN}  API Gateway REST stages:${RESET}"
      echo "$apis" | while IFS=$'\t' read -r api_id api_name; do
        [[ -z "$api_id" ]] && continue
        local stages="$(aws apigateway get-stages --region "$region" --rest-api-id "$api_id" \
          --query 'item[].stageName' --output text 2>/dev/null)"
        if [[ -z "$stages" ]]; then
          echo "    ${BOLD}$api_name${RESET} ($api_id): no stages"
          continue
        fi
        local stage="" stage_arn=""
        for stage in ${=stages}; do
          stage_arn="arn:aws:apigateway:${region}::/restapis/${api_id}/stages/${stage}"
          _audit_resource "$api_name/$stage ($api_id)" "$stage_arn" "$region" 1
        done
      done
    fi
  done

  # Clean up helper functions defined in this scope.
  unfunction _shield_status _print_webacl _audit_resource 2>/dev/null

  echo ""
  echo "${GREEN}✔ Edge security audit complete.${RESET}"
}

# --- Completion for aws_edge_security (zsh) ---
# Completes options and common AWS region names. Region names are static (fast,
# offline); edit the list below if you use regions that aren't included.
# Registered only when the zsh completion system (compinit) is loaded.
_aws_edge_security() {
  local -a opts regions
  opts=(
    '--no-cloudfront:skip the CloudFront pass'
    '--no-cf:skip the CloudFront pass'
    '-h:show help'
    '--help:show help'
  )
  regions=(
    us-east-1 us-east-2 us-west-1 us-west-2
    ca-central-1 ca-west-1 sa-east-1
    eu-central-1 eu-central-2 eu-west-1 eu-west-2 eu-west-3
    eu-south-1 eu-south-2 eu-north-1
    af-south-1 me-central-1 me-south-1 il-central-1
    ap-east-1 ap-south-1 ap-south-2
    ap-northeast-1 ap-northeast-2 ap-northeast-3
    ap-southeast-1 ap-southeast-2 ap-southeast-3 ap-southeast-4
  )
  _describe -t options 'option' opts
  _describe -t regions 'region' regions
}

# Internal helper: Displays current status, advice, and available commands
_dns_helper() {
  local servers
  servers=$(networksetup -getdnsservers Wi-Fi 2>/dev/null)

  # 1. Display Current Status
  if [[ "$servers" == *"9.9.9.9"* ]]; then
    echo "${GREEN}[✓] Status: SECURED (Quad9)${RESET}"
  elif [[ "$servers" == *"There aren't any DNS Servers set on Wi-Fi."* ]] || [[ -z "$servers" ]]; then
    echo "${BLUE}[!] Status: UNSECURED (Automatic/ISP)${RESET}"
  else
    echo "${MAGENTA}[?] Status: CUSTOM DNS${RESET}"
    echo "    Servers: $servers"
  fi

  dns_audit # Show detailed privacy audit results

  # 2. Display Available Commands
  echo "\n${BOLD_WHITE}Available Commands:${RESET}"
  echo "  ${GREEN}dns secure${RESET}  -> Switch to Quad9 (Security + Privacy)"
  echo "  ${YELLOW}dns reset${RESET}   -> Revert to Automatic (DHCP/yallo)"
  echo "  ${BLUE}dns test${RESET}    -> Run speed test against 9.9.9.9, 1.1.1.1, 8.8.8.8"
  echo "  ${BLUE}dns check${RESET}   -> Privacy Audit: Check IP & Active Resolver"
  echo "  ${BLUE}dns flush${RESET}   -> Clear local macOS DNS cache"
  echo "  ${BLUE}dns status${RESET}  -> Print raw networksetup output"
}

# Master DNS command
dns() {
  case "$1" in
    secure)  
      dns_secure_action
      echo ""
      dns_audit # Automatically run audit after securing
      ;;
    reset)   
      dns_reset_action
      echo ""
      dns_audit # Automatically run audit after resetting
      ;;
    test)    dns_speedtest ;;
    check)   dns_audit ;;
    flush)   dns_flush_action ;;
    status)  networksetup -getdnsservers Wi-Fi ;;
    *)       _dns_helper ;;
  esac
}

# Set DNS to Quad9 (Security + Privacy)
dns_secure_action() {
  echo "${YELLOW}Setting DNS to Quad9 (IPv4 + IPv6)...${RESET}"
  sudo networksetup -setdnsservers Wi-Fi 9.9.9.9 149.112.112.112 2620:fe::fe 2620:fe::9
  dns_flush_action
  echo "${GREEN}DNS is now set to Quad9.${RESET}"
}

# Reset DNS to Automatic (DHCP)
dns_reset_action() {
  echo "${YELLOW}Resetting DNS to Automatic (DHCP)...${RESET}"
  sudo networksetup -setdnsservers Wi-Fi empty
  dns_flush_action
  echo "${GREEN}DNS has been reset to network defaults.${RESET}"
}

# Flush system DNS cache
dns_flush_action() {
  sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
  echo "${GREEN}System DNS cache flushed.${RESET}"
}

# Compare latency between major providers
dns_speedtest() {
  echo "${BLUE}--- DNS Latency Test (ms) ---${RESET}"
  echo -n "Quad9 (9.9.9.9):      "
  ping -c 3 9.9.9.9 | tail -1 | awk '{print $4}' | cut -d '/' -f 2 2>/dev/null
  echo -n "Cloudflare (1.1.1.1): "
  ping -c 3 1.1.1.1 | tail -1 | awk '{print $4}' | cut -d '/' -f 2 2>/dev/null
  echo -n "Google (8.8.8.8):     "
  ping -c 3 8.8.8.8 | tail -1 | awk '{print $4}' | cut -d '/' -f 2 2>/dev/null
}

# Comprehensive Audit: Verifies VPN (Proton) and DNS Resolver (Quad9)
dns_audit() {
  echo "${YELLOW}--- Privacy Audit ---${RESET}"
  
  # Check Public IP and Provider
  local ip_info
  ip_info=$(curl -s --max-time 2 https://ipinfo.io/json)
  local public_ip=$(echo "$ip_info" | grep -o '"ip": *"[^"]*"' | cut -d'"' -f4)
  local org=$(echo "$ip_info" | grep -o '"org": *"[^"]*"' | cut -d'"' -f4)
  
  echo "Public IP:  ${BLUE}$public_ip${RESET}"
  echo "Provider:   ${BLUE}$org${RESET}"
  
  # Check DNS Resolver identity
  echo -n "DNS Resolver: "
  local resolver=$(dig +short txt whoami.lua.powerdns.org @9.9.9.9 | sed 's/"//g')
  echo "${BLUE}$resolver${RESET}"
  
  # VPN Status Logic
  if [[ "$org" == *"Proton"* || "$org" == *"Datacamp"* ]]; then
    echo "${GREEN}[✓] PROTON VPN ACTIVE: Your yallo IP is hidden.${RESET}"
  else
    echo "${RED}[!] VPN INACTIVE: You are browsing via yallo directly.${RESET}"
  fi
  
  # Quad9 Status Logic
  if [[ "$resolver" == *"9.9.9.9"* || "$resolver" == *"quad9"* || "$resolver" == *"pch"* ]]; then
    echo "${GREEN}[✓] QUAD9 ACTIVE: Your DNS requests are secure.${RESET}"
  fi
}

function checkpy_uv() {
  # Exit immediately if a command exits with a non-zero status.
  set -e

  echo "--- Running Static Checks (via uv run) ---"

  echo "[1/4] Running Ruff Linter..."
  # uv run finds 'ruff' in the project environment
  uv run ruff check . --force-exclude

  echo "[2/4] Running Ruff Formatter Check..."
  uv run ruff format --check . --force-exclude

  echo "[3/4] Running MyPy Type Checker..."
  uv run mypy . --config-file pyproject.toml

  echo "[4/4] Running Bandit Security Scanner..."
  uv run bandit -c pyproject.toml -r . -ll --quiet

  # This line will only be reached if all previous commands succeed
  echo "--- All Static Checks Passed Successfully! ---"
}

function trigger_build() {
  git commit --allow-empty -m "Trigger Build" > /dev/null 2>&1
  git push
  echo "${GREEN}Build triggered.${RESET}"
  return 0
}

alias png='pdf2png'

alias dns_secure="dns secure"
alias dnsreset="dns reset"
alias dnsstatus="dns status"
alias dnsflush="dns flush"
alias dnstest="dns test"

# --- macOS Terminal profile switching (burib-dark / burib-light) ---
# The profiles are installed by scripts/setup_mac.sh. Flips the macOS
# appearance too, because the window chrome (title/tab bar) follows the
# system dark/light mode, not the Terminal profile.
if [[ "$OSTYPE" == darwin* ]]; then
  # Which prompt config to use, tracked across shells in a one-line marker
  # (not committed - like zshrc.local, this is machine/session state).
  # Defaults to dark so a shell that has never run `dark`/`light` behaves
  # exactly as before this existed.
  POSH_THEME_MARKER="$HOME/.config/terminal-appearance"

  function _posh_config_path() {
    if [[ -f "$POSH_THEME_MARKER" ]] && [[ "$(cat "$POSH_THEME_MARKER")" == "light" ]]; then
      echo "$HOME/.config/powerlevel10k_lean_light.omp.json"
    else
      echo "$HOME/.config/powerlevel10k_lean.omp.json"
    fi
  }

  # Called at shell start (from .zshrc, after this file is sourced) and again
  # here on every `dark`/`light`, so an already-open shell's prompt updates
  # immediately instead of only on the next new shell.
  function _load_prompt_theme() {
    eval "$(oh-my-posh init zsh --config "$(_posh_config_path)")"
  }

  function switch_terminal_profile() {
    local PROFILE=$1
    local DARK_MODE=$2
    osascript \
      -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $DARK_MODE" \
      -e 'tell application "Terminal"' \
      -e "set default settings to settings set \"$PROFILE\"" \
      -e "set startup settings to settings set \"$PROFILE\"" \
      -e "set current settings of every tab of every window to settings set \"$PROFILE\"" \
      -e 'end tell'
    if [[ "$DARK_MODE" == "true" ]]; then
      echo "dark" > "$POSH_THEME_MARKER"
    else
      echo "light" > "$POSH_THEME_MARKER"
    fi
    _load_prompt_theme
  }

  alias dark="switch_terminal_profile burib-dark true"
  alias light="switch_terminal_profile burib-light false"
fi
