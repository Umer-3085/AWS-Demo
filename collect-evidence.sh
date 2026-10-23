#!/usr/bin/env bash
set -u

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <bucket-name> <ec2-address> <lambda-address>"
  exit 1
fi

BUCKET="$1"
EC2_ADDRESS="$2"
LAMBDA_ADDRESS="$3"
REGION="ap-southeast-2"
EC2_ROLE="cv-ec2-role-23l-3085"
LAMBDA_ROLE="cv-lambda-role-23l-3085"
LAMBDA_FUNCTION="cv-func-23l-3085"
SECURITY_GROUP="cv-sg-23l-3085"
INSTANCE_NAME="cv-ec2-23l-3085"
OUT="evidence.txt"

# Accept either a hostname/IP or a URL for the EC2 address.
EC2_HOST="${EC2_ADDRESS#http://}"
EC2_HOST="${EC2_HOST#https://}"
EC2_HOST="${EC2_HOST%%/*}"
EC2_URL="http://${EC2_HOST}"
S3_URL="https://${BUCKET}.s3.${REGION}.amazonaws.com/site/index.html"

export AWS_DEFAULT_REGION="$REGION"
: > "$OUT"

run_section() {
  local name="$1"
  shift
  {
    printf '== %s ==\n' "$name"
    "$@" || printf '[Command failed with exit status %s]\n' "$?"
    printf '\n'
  } >> "$OUT" 2>&1
}

ec2_policy() {
  echo "Role: $EC2_ROLE"
  local names
  names="$(aws iam list-role-policies --role-name "$EC2_ROLE" --query 'PolicyNames[]' --output text 2>&1)" || {
    echo "$names"; return 1;
  }
  if [ -z "$names" ] || [ "$names" = "None" ]; then
    echo "No inline policies found."
  else
    for p in $names; do
      echo "--- Inline policy: $p ---"
      aws iam get-role-policy --role-name "$EC2_ROLE" --policy-name "$p" || true
    done
  fi
  echo "--- Attached managed policies ---"
  aws iam list-attached-role-policies --role-name "$EC2_ROLE"
}

lambda_policy() {
  echo "Role: $LAMBDA_ROLE"
  echo "--- Attached managed policies ---"
  aws iam list-attached-role-policies --role-name "$LAMBDA_ROLE" || true
  echo "--- Inline policies ---"
  local names
  names="$(aws iam list-role-policies --role-name "$LAMBDA_ROLE" --query 'PolicyNames[]' --output text 2>&1)" || {
    echo "$names"; return 1;
  }
  if [ -z "$names" ] || [ "$names" = "None" ]; then
    echo "No inline policies found."
  else
    for p in $names; do
      echo "--- Inline policy: $p ---"
      aws iam get-role-policy --role-name "$LAMBDA_ROLE" --policy-name "$p" || true
    done
  fi
}

endpoints() {
  echo "--- EC2 / ---"
  curl -sS -o /dev/null -w 'HTTP %{http_code}; content-type %{content_type}\n' "${EC2_URL}/" || true
  echo "--- EC2 /style.css ---"
  curl -sS -o /dev/null -w 'HTTP %{http_code}; content-type %{content_type}\n' "${EC2_URL}/style.css" || true
  echo "--- EC2 /cv.pdf ---"
  curl -sS -o /dev/null -w 'HTTP %{http_code}; content-type %{content_type}\n' "${EC2_URL}/cv.pdf" || true
  echo "--- Lambda / ---"
  curl -sS -o /dev/null -w 'HTTP %{http_code}; content-type %{content_type}\n' "${LAMBDA_ADDRESS%/}/" || true
  echo "--- Lambda /style.css ---"
  curl -sS -o /dev/null -w 'HTTP %{http_code}; content-type %{content_type}\n' "${LAMBDA_ADDRESS%/}/style.css" || true
  echo "--- Lambda /cv.pdf ---"
  curl -sS -o /dev/null -w 'HTTP %{http_code}; content-type %{content_type}\n' "${LAMBDA_ADDRESS%/}/cv.pdf" || true
  echo "--- Lambda /anything (expected 404) ---"
  curl -sS -o /dev/null -w 'HTTP %{http_code}; content-type %{content_type}\n' "${LAMBDA_ADDRESS%/}/anything" || true
  echo "--- Direct S3 object (expected 403/AccessDenied) ---"
  curl -sS -o /dev/null -w 'HTTP %{http_code}; content-type %{content_type}\n' "$S3_URL" || true
}

instance_details() {
  local id
  id="$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].InstanceId' --output text)"
  if [ -z "$id" ] || [ "$id" = "None" ]; then
    echo "Could not find a running instance tagged Name=$INSTANCE_NAME."
    echo "Check the instance Name tag or update INSTANCE_NAME in this script."
    return 1
  fi
  aws ec2 describe-instances --instance-ids "$id" \
    --query 'Reservations[].Instances[].{InstanceId:InstanceId,InstanceType:InstanceType,State:State.Name,PublicIpAddress:PublicIpAddress,IamInstanceProfile:IamInstanceProfile.Arn,MetadataOptions:MetadataOptions,SecurityGroups:SecurityGroups[].GroupId,Tags:Tags}' \
    --output json
}

security_group() {
  aws ec2 describe-security-groups --group-names "$SECURITY_GROUP" \
    --query 'SecurityGroups[].{GroupId:GroupId,GroupName:GroupName,Inbound:IpPermissions}' --output json
}

lambda_logs() {
  aws logs tail "/aws/lambda/$LAMBDA_FUNCTION" --since 1d --format short
}

log_retention() {
  aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/$LAMBDA_FUNCTION" \
    --query 'logGroups[].{LogGroupName:logGroupName,RetentionInDays:retentionInDays}' --output table
}

run_section "caller" aws sts get-caller-identity
run_section "public-access" aws s3api get-public-access-block --bucket "$BUCKET"
run_section "versioning" aws s3api get-bucket-versioning --bucket "$BUCKET"
run_section "objects" aws s3 ls "s3://$BUCKET/site/"
run_section "ec2-policy" ec2_policy
run_section "lambda-policy" lambda_policy
run_section "security-group" security_group
run_section "instance" instance_details
run_section "endpoints" endpoints
run_section "lambda-logs" lambda_logs
run_section "log-retention" log_retention

echo "DONE"
