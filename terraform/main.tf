terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket = "itsuki-github-actions-terraform-lab-2026-tfstate"
    key    = "github-actions-oidc-ci/terraform.tfstate"
    region = "ap-northeast-1"
  }
}

provider "aws" {
  region = var.aws_region
}

resource "aws_s3_bucket" "main" {
  bucket = var.bucket_name

  tags = {
    Name    = "github-actions-terraform-lab"
    Project = "project3"
  }
}