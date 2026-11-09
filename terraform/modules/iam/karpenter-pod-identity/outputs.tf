output "role_arn" {
  description = "Karpenter controller IAM role ARN"
  value       = aws_iam_role.karpenter.arn
}

output "association_id" {
  description = "EKS Pod Identity association ID"
  value       = aws_eks_pod_identity_association.karpenter.association_id
}
