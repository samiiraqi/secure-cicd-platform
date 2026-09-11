#!/usr/bin/env bash
# Creates the S3 bucket + DynamoDB table used as the Terraform remote state
# backend for this project (environments/*/backend.tf). Run this ONCE per
# AWS account, before the first `terraform init` in any environment.
#
# Usage:
#   ./scripts/bootstrap-backend.sh [region]
#
set -euo pipefail

REGION="${1:-us-east-1}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="secure-cicd-tfstate-${ACCOUNT_ID}"
TABLE="secure-cicd-tf-locks"

echo "Account:  ${ACCOUNT_ID}"
echo "Region:   ${REGION}"
echo "Bucket:   ${BUCKET}"
echo "Table:    ${TABLE}"
echo

if aws s3api head-bucket --bucket "${BUCKET}" 2>/dev/null; then
  echo "S3 bucket ${BUCKET} already exists, skipping creation."
else
  echo "Creating S3 bucket ${BUCKET}..."
  if [[ "${REGION}" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "${BUCKET}" --region "${REGION}"
  else
    aws s3api create-bucket --bucket "${BUCKET}" --region "${REGION}" \
      --create-bucket-configuration LocationConstraint="${REGION}"
  fi

  aws s3api put-bucket-versioning --bucket "${BUCKET}" \
    --versioning-configuration Status=Enabled

  aws s3api put-bucket-encryption --bucket "${BUCKET}" \
    --server-side-encryption-configuration '{
      "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "aws:kms"}, "BucketKeyEnabled": true}]
    }'

  aws s3api put-public-access-block --bucket "${BUCKET}" \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
fi

if aws dynamodb describe-table --table-name "${TABLE}" --region "${REGION}" >/dev/null 2>&1; then
  echo "DynamoDB table ${TABLE} already exists, skipping creation."
else
  echo "Creating DynamoDB table ${TABLE} for state locking..."
  aws dynamodb create-table \
    --table-name "${TABLE}" \
    --region "${REGION}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --sse-specification Enabled=true
fi

echo
echo "Done. Update the 'bucket' field in environments/*/backend.tf to:"
echo "  ${BUCKET}"
echo "(or pass it via -backend-config=\"bucket=${BUCKET}\" at 'terraform init' time)"
