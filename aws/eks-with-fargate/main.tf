################################################################################
# EKS with Fargate profiles
#
# Pattern: managed control plane + Fargate pods for stateless workloads,
# managed node group for things Fargate can't run (DaemonSets, GPU, etc).
#
# Why two compute types: Fargate gives you per-pod billing and zero node ops,
# but doesn't support DaemonSets (CNI, log shipper, metrics agent). So you
# pretty much always need at least one small managed node group alongside.
################################################################################

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

variable "name"   { type = string }
variable "region" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "kubernetes_version" {
  type    = string
  default = "1.30"
}

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_iam_role" "cluster" {
  name = "${var.name}-eks-cluster"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_eks_cluster" "this" {
  name     = var.name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = false
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  # Enable control-plane log shipping. Cheap insurance for "why did the
  # API server start 429ing at 3am" investigations.
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  encryption_config {
    provider { key_arn = aws_kms_key.eks.arn }
    resources = ["secrets"]
  }

  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}

resource "aws_kms_key" "eks" {
  description             = "EKS secrets encryption for ${var.name}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

################################################################################
# Fargate profile — default to running everything in kube-system + apps NS
################################################################################

resource "aws_iam_role" "fargate" {
  name = "${var.name}-fargate"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "eks-fargate-pods.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "fargate_policy" {
  role       = aws_iam_role.fargate.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
}

resource "aws_eks_fargate_profile" "apps" {
  cluster_name           = aws_eks_cluster.this.name
  fargate_profile_name   = "apps"
  pod_execution_role_arn = aws_iam_role.fargate.arn
  subnet_ids             = var.private_subnet_ids

  selector { namespace = "apps" }
  selector { namespace = "kube-system" }
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  value     = aws_eks_cluster.this.certificate_authority[0].data
  sensitive = true
}
