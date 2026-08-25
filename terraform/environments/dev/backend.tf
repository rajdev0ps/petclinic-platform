# Remote state backend — partial configuration.
# All connection values (bucket, region, dynamodb_table) are provided at init time
# via a backend.hcl file (gitignored — never commit it).
#
# First-time setup:
#   1. Run terraform in terraform/bootstrap/ to create the S3 bucket and DynamoDB table.
#   2. Copy terraform/environments/dev/backend.hcl.example to backend.hcl and fill in the values
#      (or run scripts/setup-env.sh which generates it automatically).
#   3. terraform init -backend-config=backend.hcl
#
# The key is the only value baked in — it is not sensitive and never changes.
terraform {
  backend "s3" {
    key     = "petclinic/dev/terraform.tfstate"
    encrypt = true
  }
}
