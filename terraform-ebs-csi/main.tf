# ==========================================================
# EBS CSI DRIVER - IAM ROLE
# ==========================================================

data "aws_iam_policy_document" "ebs_csi_assume_role" {
  statement {
    sid    = "AllowEksPodIdentity"
    effect = "Allow"
    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${data.aws_eks_cluster.existing.name}-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json

  tags = {
    Name = "${data.aws_eks_cluster.existing.name}-ebs-csi-role"
  }
}

# ==========================================================
# EBS CSI DRIVER - IAM POLICY
# ==========================================================

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# ==========================================================
# EBS CSI DRIVER - EKS ADDON + POD IDENTITY
# ==========================================================

resource "aws_eks_addon" "ebs_csi" {
  cluster_name = data.aws_eks_cluster.existing.name
  addon_name   = "aws-ebs-csi-driver"

  pod_identity_association {
    service_account = "ebs-csi-controller-sa"
    role_arn        = aws_iam_role.ebs_csi.arn
  }

  depends_on = [
    aws_iam_role_policy_attachment.ebs_csi
  ]

  tags = {
    Name = "${data.aws_eks_cluster.existing.name}-ebs-csi"
  }
}
