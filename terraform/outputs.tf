output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  value = aws_eks_cluster.main.version
}

output "existing_vpc_id" {
  value = data.aws_vpc.existing.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "bootstrap_node_group" {
  value = aws_eks_node_group.bootstrap.node_group_name
}

output "karpenter_node_role_arn" {
  value = data.aws_iam_role.karpenter_node.arn
}

# ==========================================================
# EBS CSI OUTPUTS
# ==========================================================

output "ebs_csi_role_arn" {
  description = "IAM role used by the EBS CSI controller"
  value       = aws_iam_role.ebs_csi.arn
}

output "ebs_csi_addon_status" {
  description = "EBS CSI add-on status"
  value       = aws_eks_addon.ebs_csi.status
}
