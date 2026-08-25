variable "region" {
  description = "AWS region where the state bucket and lock table are created. Must match the region used by all environment configs."
  type        = string
}
