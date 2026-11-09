variable "role_name" {
  description = "IAM role assumed by the Karpenter controller"
  type        = string
  default     = "KarpenterControllerRole-eks-arm64-platform"
}

variable "cluster_name" {
  description = "Existing EKS cluster name"
  type        = string
}

variable "namespace" {
  description = "Karpenter controller namespace"
  type        = string
  default     = "kube-system"
}

variable "service_account" {
  description = "Karpenter controller service account"
  type        = string
  default     = "karpenter"
}
