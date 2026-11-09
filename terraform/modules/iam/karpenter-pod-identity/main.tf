resource "aws_iam_role" "karpenter" {
  name = var.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Principal = {
        Service = "pods.eks.amazonaws.com"
      }

      Action = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
    }]
  })

  tags = {
    Name      = var.role_name
    Project   = "eks-arm64-platform-automation"
    ManagedBy = "Terraform"
  }
}

resource "aws_eks_pod_identity_association" "karpenter" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account
  role_arn        = aws_iam_role.karpenter.arn

  tags = {
    Name      = "karpenter-pod-identity"
    Project   = "eks-arm64-platform-automation"
    ManagedBy = "Terraform"
  }
}
