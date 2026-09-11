# Remote state backend. The bucket/table below must exist BEFORE `terraform
# init` (Terraform can't create the backend that stores its own state) -
# run scripts/bootstrap-backend.sh once per AWS account, or override these
# values at init time:
#
#   terraform init \
#     -backend-config="bucket=<your-bucket>" \
#     -backend-config="dynamodb_table=<your-lock-table>"
#
terraform {
  backend "s3" {
    bucket         = "secure-cicd-tfstate-REPLACE_WITH_ACCOUNT_ID"
    key            = "staging/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "secure-cicd-tf-locks"
    encrypt        = true
  }
}
