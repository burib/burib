function empty_s3_bucket() {
  local BUCKET_NAME=$1
  aws s3api delete-objects \
    --bucket "$BUCKET_NAME" \
    --delete "$(aws s3api list-object-versions \
      --bucket "${BUCKET_NAME}" \
      --max-items 1000000 \
      --output=json \
      --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" >/dev/null 2>&1
}

function delete_s3_bucket() {
  local BUCKET_NAME=$1
  aws s3 rb "s3://$BUCKET_NAME" --force
}

function remove_all_versions_of_s3_object() {
  bucket=$1

  if [ -z "$bucket" ]; then
    echo "Bucket name is required."
    return 1
  fi

  echo "Removing all versions from bucket: $bucket"

  # List all object versions in the bucket
  versions=$(aws s3api list-object-versions --bucket "$bucket" --query 'Versions')

  if [ -z "$versions" ]; then
    echo "No versions found in bucket $bucket."
    return 1
  fi

  # Loop through each version and delete it
  echo "$versions" | jq -c '.[]' | while read -r version; do
    key=$(echo "$version" | jq -r '.Key')
    version_id=$(echo "$version" | jq -r '.VersionId')

    echo "Deleting version $version_id of object $key"
    aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version_id"
  done

  # List all delete markers in the bucket
  delete_markers=$(aws s3api list-object-versions --bucket "$bucket" --query 'DeleteMarkers')

  if [ -n "$delete_markers" ]; then
    # Loop through each delete marker and remove it
    echo "$delete_markers" | jq -c '.[]' | while read -r marker; do
      key=$(echo "$marker" | jq -r '.Key')
      version_id=$(echo "$marker" | jq -r '.VersionId')

      echo "Removing delete marker $version_id of object $key"
      aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version_id"
    done
  fi

  echo "All versions and delete markers removed from bucket: $bucket"
}

function empty_s3_bucket_with_lifecycle_policy() {
  local BUCKET_NAME=$1
  local lifecycle_policy='
{
  "Rules": [
    {
      "Expiration": {
        "Days": 1
      },
      "ID": "FullDelete",
      "Filter": {
        "Prefix": ""
      },
      "Status": "Enabled",
      "NoncurrentVersionExpiration": {
        "NoncurrentDays": 1
      },
      "AbortIncompleteMultipartUpload": {
        "DaysAfterInitiation": 1
      }
    },
    {
      "Expiration": {
        "ExpiredObjectDeleteMarker": true
      },
      "ID": "DeleteMarkers",
      "Filter": {
        "Prefix": ""
      },
      "Status": "Enabled"
    }
  ]
}'
  aws s3api put-bucket-lifecycle-configuration \
    --bucket "$BUCKET_NAME" \
    --lifecycle-configuration "${lifecycle_policy}" >/dev/null 2>&1
}


function delete_objects_older_than_7_days() {
  local BUCKET_NAME=$1
  local lifecycle_policy='
{
  "Rules": [
    {
      "Expiration": {
        "Days": 7
      },
      "ID": "DeleteObjectsAfter7Days",
      "Filter": {
        "Prefix": ""
      },
      "Status": "Enabled",
      "NoncurrentVersionExpiration": {
        "NoncurrentDays": 7
      },
      "AbortIncompleteMultipartUpload": {
        "DaysAfterInitiation": 1
      }
    },
    {
      "Expiration": {
        "ExpiredObjectDeleteMarker": true
      },
      "ID": "DeleteMarkers",
      "Filter": {
        "Prefix": ""
      },
      "Status": "Enabled"
    }
  ]
}'
  aws s3api put-bucket-lifecycle-configuration \
    --bucket "$BUCKET_NAME" \
    --lifecycle-configuration "${lifecycle_policy}" >/dev/null 2>&1
}

function list_s3_buckets() {
  aws s3api list-buckets --query 'Buckets[*].Name' --output json | jq -r '.[]'
}

function empty_s3_bucket_and_delete() {
  local BUCKET_NAME=$1
  empty_s3_bucket "$BUCKET_NAME"
  delete_s3_bucket "$BUCKET_NAME"
}

function empty_s3_buckets() {
  local BUCKETS_TO_EMPTY
  BUCKETS_TO_EMPTY=$(list_s3_buckets)

  # iterate over each bucket and empty it
#  echo -e "The following buckets will be emptied:\n"
#  while IFS= read -r bucket; do
#    echo "$bucket"
#  done <<< "$BUCKETS_TO_EMPTY"

#  echo -e "\nDo you want to empty all s3 buckets? (y/n OR yes/no or Y/N)\n"
#  read -r response

#  if [[ "$response" == "y" || "$response" == "yes" || "$response" == "Y" || "$response" == "YES" ]]; then
    while IFS= read -r bucket; do
      echo "Emptying $bucket"
      empty_s3_bucket "$bucket"
    done <<< "$BUCKETS_TO_EMPTY"
#  else
#    echo "Exiting"
#  fi

}
