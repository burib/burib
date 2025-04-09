#!/bin/zsh
# ~/.config/zsh/my_dev_utils.sh
#
# Utility functions and aliases for development workflows (Git, Terraform, etc.)
# Source this file from your .zshrc:
#   source /path/to/this/file/my_dev_utils.sh

# --- Git Functions ---

# Get current Git branch and copy to clipboard
function current_branch() {
  local current_branch
  # Try symbolic-ref first, fallback to branch --show-current
  current_branch=$(git symbolic-ref --short HEAD 2>/dev/null || git branch --show-current 2>/dev/null)

  if [[ -z "$current_branch" ]]; then
    echo "\033[0;31mError: Not on a branch or not in a git repository.\033[0m" >&2
    return 1 # Indicate failure
  fi

  # Clipboard compatibility (macOS vs Linux)
  if command -v pbcopy &> /dev/null; then
    echo "$current_branch" | pbcopy
    echo "\033[0;33m'$current_branch' copied to macOS clipboard.\033[0m"
  elif command -v xclip &> /dev/null; then
    echo "$current_branch" | xclip -selection clipboard
    echo "\033[0;33m'$current_branch' copied to X clipboard.\033[0m"
  elif command -v xsel &> /dev/null; then
    echo "$current_branch" | xsel --clipboard --input
    echo "\033[0;33m'$current_branch' copied to X clipboard.\033[0m"
  else
    echo "\033[0;33m'$current_branch' (clipboard command not found).\033[0m"
  fi
  return 0 # Indicate success
}

# Rebase current branch onto a target branch (default: main)
function rebase_on() {
  local target_branch="${1:-main}" # Default to main if no arg given
  local current_branch

  current_branch=$(git symbolic-ref --short HEAD 2>/dev/null || git branch --show-current 2>/dev/null)

  if [[ -z "$current_branch" ]]; then
    echo "\033[0;31mError: Could not determine current branch. Not in a git repository?\033[0m" >&2
    return 1
  fi

  if [[ "$current_branch" == "$target_branch" ]]; then
    echo "\033[0;33mAlready on '$target_branch'. Pulling...\033[0m"
    git pull || { echo "\033[0;31mError: Failed to pull '$target_branch'.\033[0m" >&2; return 1; }
    echo "\033[0;32mPull successful on '$target_branch'.\033[0m"
    return 0
  fi

  echo "Rebasing '$current_branch' onto '$target_branch'..."

  # Checkout target branch
  echo "--> Checking out '$target_branch'..."
  git checkout "$target_branch" || { echo "\033[0;31mError: Failed to checkout '$target_branch'.\033[0m" >&2; git checkout "$current_branch" &>/dev/null; return 1; } # Try to go back

  # Pull target branch
  echo "--> Pulling latest changes for '$target_branch'..."
  git pull || { echo "\033[0;31mError: Failed to pull '$target_branch'.\033[0m" >&2; git checkout "$current_branch" &>/dev/null; return 1; } # Try to go back

  # Checkout original branch
  echo "--> Checking out '$current_branch'..."
  git checkout "$current_branch" || { echo "\033[0;31mError: Failed to checkout back to '$current_branch'.\033[0m" >&2; return 1; }

  # Rebase
  echo "--> Rebasing '$current_branch' onto '$target_branch'..."
  git rebase "$target_branch" || { echo "\033[0;31mError: Rebase failed. Please resolve conflicts and run 'git rebase --continue' or 'git rebase --abort'.\033[0m" >&2; return 1; }

  echo "\033[0;32mSuccessfully rebased '$current_branch' onto '$target_branch'.\033[0m"
  return 0
}

# Checkout main and pull
function main() {
  echo "Switching to main and pulling..."
  git checkout main || { echo "\033[0;31mError: Failed to checkout main.\033[0m" >&2; return 1; }
  git pull || { echo "\033[0;31mError: Failed to pull main.\033[0m" >&2; return 1; }
  echo "\033[0;32mSwitched to main and pulled successfully.\033[0m"
  return 0
}

# Format, add all changes, and commit
function commit() {
  local MESSAGE="$1"
  if [[ -z "$MESSAGE" ]]; then
    echo "\033[0;31mError: Commit message is required.\033[0m" >&2
    echo "Usage: commit \"Your commit message\"" >&2
    return 1
  fi

  # Run Terraform fmt if in a Terraform project (optional, consider adding check)
  if [[ -f *.tf || -d .terraform ]]; then
      echo "--> Running terraform fmt recursively..."
      terraform fmt --recursive
  fi

  echo "--> Committing with message: '$MESSAGE'"
  # Note: -a stages all tracked, modified files.
  # Removed --no-verify by default for safety (respects hooks). Use 'force_commit' alias to bypass.
  git commit -am "$MESSAGE" || { echo "\033[0;31mError: Git commit failed.\033[0m" >&2; return 1; }
  echo "\033[0;32mCommit successful.\033[0m"
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
    echo "\033[0;31mError: Branch name is required.\033[0m" >&2
    echo "Usage: new <new-branch-name>" >&2
    return 1
  fi
  git checkout -b "$branch_name" || { echo "\033[0;31mError: Failed to create branch '$branch_name'. Does it already exist?\033[0m" >&2; return 1; }
  echo "\033[0;32mSwitched to a new branch '$branch_name'.\033[0m"
  return 0
}

# --- Terraform Functions & Aliases ---

# Terraform Init aliases
alias init_prod="terraform init -backend-config=environments/prod.tfbackend"
alias init_dev="terraform init -backend-config=environments/dev.tfbackend"

# Terraform Plan aliases
alias plan="terraform plan"
alias plan_dev='echo -e "\n\033[0;34m--- Planning DEV Environment --- \033[0m\n" && terraform plan -var-file=environments/dev.tfvars'
alias plan_prod='echo -e "\n\033[0;31m--- Planning PROD Environment --- \033[0m\n" && terraform plan -var-file=environments/prod.tfvars'
# This alias assumes 'terraform plan' without var-file is desired for prod after init_prod
# Or maybe it refers to a Terraform Cloud/Enterprise remote plan execution? Clarify based on your workflow.
alias plan_prod_remote='echo -e "\n\033[0;31m--- Planning PROD Environment (Remote State Default Vars) --- \033[0m\n" && terraform plan'

# Terraform Apply aliases - REMOVED --auto-approve FOR SAFETY
# Add --auto-approve back ONLY if you FULLY understand and accept the risks, especially for PROD.
alias apply="terraform apply"
alias apply_dev='echo -e "\n\033[0;34m--- Applying DEV Environment --- \033[0m\n" && terraform apply -var-file=environments/dev.tfvars'
alias apply_prod='echo -e "\n\033[0;31m*** Applying PROD Environment *** CAUTION! *** \033[0m\n" && terraform apply -var-file=environments/prod.tfvars'
alias apply_prod_remote='echo -e "\n\033[0;31m*** Applying PROD Environment (Remote State Default Vars) *** CAUTION! *** \033[0m\n" && terraform apply'

# Terraform Destroy aliases - CORRECTED & ADDED WARNING
# Add --auto-approve ONLY if you understand the risks for DEV. NEVER for PROD.
alias destroy_dev='echo -e "\n\033[1;31m*** DESTROYING DEV ENVIRONMENT *** ARE YOU SURE? ***\033[0m\n" && terraform destroy -var-file=environments/dev.tfvars'
# Example with auto-approve for DEV (use with extreme caution):
# alias destroy_dev_auto='echo -e "\n\033[1;31m*** DESTROYING DEV ENVIRONMENT (AUTO-APPROVED) ***\033[0m\n" && terraform destroy -var-file=environments/dev.tfvars --auto-approve'

# Terraform fmt alias
alias fmt="terraform fmt --recursive"

# Terraform Unlock function
function unlock() {
  local LOCK_ID="$1"
  if [[ -z "$LOCK_ID" ]]; then
     echo "\033[0;31mError: Lock ID is required.\033[0m" >&2
     echo "Usage: unlock <LOCK_ID>" >&2
     echo "Hint: Run 'terraform plan' or 'terraform apply' to see the Lock ID if locked." >&2
     return 1
  fi
  echo "\033[0;33mAttempting to force-unlock Lock ID: $LOCK_ID\033[0m"
  terraform force-unlock -force "$LOCK_ID"
}

# --- General Aliases ---

alias branch="current_branch"
alias rebase="rebase_on main" # Default rebase points to main
alias rebase_main="rebase_on main"
alias rebase_master="rebase_on master"
alias force_commit='echo "\033[0;33mBypassing pre-commit hooks (--no-verify)\033[0m" && commit --no-verify' # Alias to commit WITH --no-verify

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

# Converts input lines to Sentence Case (first letter of first word capitalized, rest lower)
# This version processes line by line and only uppercases the very first letter.
function sentenceCase() {
    while read -r line; do
        local string="$line"
        # Trim leading/trailing whitespace first
        string="$(echo -e "${string}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        if [[ -n "$string" ]]; then
            local first_char="${string:0:1}"
            local rest_chars="${string:1}"
            # Uppercase first char, lowercase the rest
            echo "$(echo "$first_char" | tr '[:lower:]' '[:upper:]')$(echo "$rest_chars" | tr '[:upper:]' '[:lower:]')"
        else
            echo "" # Output empty line if input was empty/whitespace
        fi
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

# Generate a lowercase UUID
uuid() {
  # Check if uuidgen exists
  if command -v uuidgen &> /dev/null; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  else
    echo "\033[0;31mError: 'uuidgen' command not found.\033[0m" >&2
    return 1
  fi
}


# --- GitHub Org Utilities ---

# Clone or update all non-archived repositories from a GitHub organization
function clone_all_org_repos() {
  # Check for required tools
  if ! command -v gh &> /dev/null; then echo "Error: GitHub CLI 'gh' not found." >&2; return 1; fi
  if ! command -v jq &> /dev/null; then echo "Error: 'jq' not found." >&2; return 1; fi
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
      echo "\033[0;31mError: Failed to fetch repository list using 'gh repo list'. Check org name and permissions.\033[0m" >&2
      return 1
  fi

  if [[ -z "$repo_id_list" ]]; then
      echo "\033[0;33mNo non-archived repositories found for organization '$org_name' or you may lack permissions.\033[0m"
      return 0
  fi

  echo "Target directory: '$target_dir'"
  mkdir -p "$target_dir" || { echo "\033[0;31mError: Failed to create target directory '$target_dir'.\033[0m" >&2; return 1; }

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
        echo " \033[0;32m-> Update successful for '$repo_name'.\033[0m"
        update_count=$((update_count + 1))
      else
        echo " \033[0;31mError: Failed to update '$repo_name'. Check for conflicts or errors above.\033[0m" >&2
        fail_count=$((fail_count + 1))
      fi
    elif [[ -e "$clone_path" ]]; then
       # Path exists but is not a git repository or a broken symlink etc.
       echo " \033[0;33mWarning: Path '$clone_path' exists but is not a git repository. Skipping '$repo_name'.\033[0m" >&2
       skip_count=$((skip_count + 1))
    else
      # Directory does not exist, clone it using gh repo clone
      echo " -> Cloning '$repo_id' into '$clone_path'..."
      # gh repo clone OWNER/REPO TARGET_DIRECTORY
      if gh repo clone "$repo_id" "$clone_path"; then
        echo " \033[0;32m-> Clone successful for '$repo_name'.\033[0m"
        success_count=$((success_count + 1))
      else
        echo " \033[0;31mError: Failed to clone '$repo_name' using 'gh repo clone'.\033[0m" >&2
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
      echo "\033[0;31mSome operations failed. Please review the output above.\033[0m"
      return 1 # Return error code if any operation failed
  fi
  return 0
}

# Optional: Add an alias for convenience
alias clone_org=clone_all_org_repos

# --- End of Script ---
echo "Development utilities loaded." # Optional: Confirmation message
