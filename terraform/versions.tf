terraform {
  required_version = ">= 1.6.0"
  required_providers {
    # Pin provider versions: upgrades become deliberate, reviewed changes.
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.13"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
  }
  # Real teams store state remotely (S3 + DynamoDB lock, Terraform Cloud, GCS...).
  # For this local lab, state stays in terraform.tfstate (git-ignored!).
}
