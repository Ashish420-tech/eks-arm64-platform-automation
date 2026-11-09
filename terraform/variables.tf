variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "cluster_name" {
  type    = string
  default = "eks-arm64-platform"
}

variable "kubernetes_version" {
  type    = string
  default = "1.36"
}

variable "existing_vpc_id" {
  description = "Existing VPC to reuse; Terraform will not own or delete it."
  type        = string
  default     = "vpc-0f1f4651b2947cf30"
}

variable "public_access_cidrs" {
  description = "Trusted IPv4 CIDRs allowed to access the EKS public API."
  type        = list(string)

  validation {
    condition = length(var.public_access_cidrs) > 0 && alltrue([
      for cidr in var.public_access_cidrs : can(cidrnetmask(cidr))
    ])
    error_message = "Provide at least one valid IPv4 CIDR."
  }
}

variable "bootstrap_instance_type" {
  type    = string
  default = "t4g.small"
}
