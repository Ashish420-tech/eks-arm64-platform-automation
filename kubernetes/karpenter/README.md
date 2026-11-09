# Karpenter prerequisites

Before applying these manifests:

1. Install Karpenter CRDs and controller.
2. Create the controller IAM role and complete controller permissions.
3. Create the EKS Pod Identity association for kube-system/karpenter.
4. Create the Karpenter node IAM role.
5. Ensure VPC subnets and security groups have the discovery tag.
6. Verify the Karpenter controller runs on the bootstrap node.

The EC2NodeClass uses a shared discovery configuration. NodePool
requirements select t4g.small for ARM64 and t3.small for AMD64.

Verify actual EC2 offering availability in ap-south-1 before testing.
