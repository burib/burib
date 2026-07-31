function init() {
  echo "profile.sh loaded" > /dev/null 2>&1
}

function check_default_profile() {
  if [[ -z "$AWS_DEFAULT_PROFILE" ]]; then
    echo "No profile set"
  else
    use "$AWS_DEFAULT_PROFILE"
    echo "$AWS_DEFAULT_PROFILE"
  fi
}

# Named aws_who, not who: a `who` function shadows /usr/bin/who.
function aws_who() {
  printf "
########### Welcome ###########
  AccountID:\t$(get_aws_account_id)
  AccountAlias:\t$(get_aws_account_aliases)
  AccountArn:\t$(get_aws_account_arn)
  IAM UserName:\t$(get_aws_iam_username)
  Region:\t$(get_aws_region)
#############################\n"
}

function get_aws_account_id() {
  aws sts get-caller-identity --query Account --output text
}

function get_aws_account_arn() {
  aws sts get-caller-identity --query Arn --output text
}

function get_aws_account_aliases() {
  aws iam list-account-aliases --query AccountAliases --output text
}

function set_aws_account_alias() {
  local ACCOUNT_ALIAS=$1
  aws iam create-account-alias --account-alias "$ACCOUNT_ALIAS"
}

function get_aws_iam_username() {
  aws iam get-user --query User.UserName --output text > /dev/null 2>&1 &
}

function get_aws_region() {
  aws configure get region
}
function set_aws_region() {
  local REGION=$1
  aws configure set region "$REGION"
}

function list() {
  aws configure list-profiles
}

# Named aws_reset, not reset: a `reset` function shadows /usr/bin/reset, which is
# what you need when the terminal gets garbled by stray control characters.
function aws_reset() {
  echo "reseting aws profile settings..."
  unset AWS_ACCESS_KEY_ID
  unset AWS_SECRET_ACCESS_KEY

  unset AWS_DEFAULT_PROFILE
  unset AWS_PROFILE

  unset AWS_SESSION_TOKEN
  unset AWS_SECURITY_TOKEN
}

function assume_role() {
  local ROLE_ARN=$1

  local json=$(aws sts assume-role --role-arn "$ROLE_ARN" --role-session-name "balazs-assumed-role")
  export AWS_ACCESS_KEY_ID=$(echo $json | jq -r '.Credentials.AccessKeyId')
  export AWS_SECRET_ACCESS_KEY=$(echo $json | jq -r '.Credentials.SecretAccessKey')
  export AWS_SESSION_TOKEN=$(echo $json | jq -r '.Credentials.SessionToken')
  export AWS_SECURITY_TOKEN="$AWS_SESSION_TOKEN"

  aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID" --profile default
  aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY" --profile default
  aws configure set aws_session_token "$AWS_SESSION_TOKEN" --profile default
}

function use_profile() {
  local PROFILE=$1
  # reset
  local access_key=$(aws configure get aws_access_key_id --profile "$PROFILE")
  local secret_access_key=$(aws configure get aws_secret_access_key --profile "$PROFILE")
  local role_arn=$(aws configure get role_arn --profile "$PROFILE")
  local source_profile=$(aws configure get source_profile --profile "$PROFILE")

  if [[ -z "$access_key" ]]; then
    local json="$(aws sts assume-role --profile "$source_profile" --role-arn "$role_arn" --role-session-name "$PROFILE")"

    export AWS_ACCESS_KEY_ID=$(echo $json | jq -r '.Credentials.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo $json | jq -r '.Credentials.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo $json | jq -r '.Credentials.SessionToken')
    export AWS_SECURITY_TOKEN="$AWS_SESSION_TOKEN"

    aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID" --profile default
    aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY" --profile default
    aws configure set aws_session_token "$AWS_SESSION_TOKEN" --profile default
    # TODO: backup previous default profile if there was any
  else
    export AWS_ACCESS_KEY_ID=$access_key
    export AWS_SECRET_ACCESS_KEY=$secret_access_key

    # TODO: backup previous default profile if there was any
    aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID" --profile default
    aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY" --profile default

    aws_who
  fi
}

function use {
  local AVAILABLE_PROFILES=$(list)
  local PROFILE=$1

  if [[ -z "$PROFILE" ]]; then
    check_default_profile
  else
    if [[ ${AVAILABLE_PROFILES[*]} =~ (^|[[:space:]])"$PROFILE"($|[[:space:]]) ]]; then
      use_profile "$PROFILE"
    else
        echo "Selected profile '$PROFILE' is not configured in ~/.aws/credentials or ~/.aws/config";
        echo "Available profiles are:"
        echo "$AVAILABLE_PROFILES"
    fi
  fi
}
