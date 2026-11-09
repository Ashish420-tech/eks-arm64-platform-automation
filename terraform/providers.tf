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
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "eks-arm64-platform-automation"
      Environment = "learning"
      ManagedBy   = "Terraform"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_vpc" "existing" {
  id = var.existing_vpc_id
}

data "aws_iam_role" "karpenter_node" {
  name = "KarpenterNodeRole-eks-arm64-platform"
}
