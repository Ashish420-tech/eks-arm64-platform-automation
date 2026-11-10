terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"

  default_tags {
    tags = {
      Project     = "eks-arm64-platform-automation"
      Environment = "learning"
      ManagedBy   = "Terraform"
    }
  }
}

data "aws_eks_cluster" "existing" {
  name = "eks-arm64-platform"
}
