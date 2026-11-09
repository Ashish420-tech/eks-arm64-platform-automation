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
