# Remote state backend — partial configuration.
# See terraform/environments/dev/backend.tf for full setup instructions.
terraform {
  backend "s3" {
    key     = "petclinic/prod/terraform.tfstate"
    encrypt = true
  }
}
