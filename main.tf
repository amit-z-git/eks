terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.41"
    }
  }
  backend "s3" {
    bucket = "tfpocbucket001"
    key    = "eks/terraform.tfstate"
    region = "eu-north-1"
  }
}

data "aws_availability_zones" "available" {}

locals {
  region   = "ap-south-2"
  name     = "amit-eks-cluster"
  vpc_cidr = "10.123.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)
  tags = {
    Name = local.name
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.16.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]
  intra_subnets   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 52)]

  enable_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

# module "eks" {
#   source          = "terraform-aws-modules/eks/aws"
#   version         = "20.29.0"
#   cluster_name    = local.name
#   cluster_version = "1.31"
#   subnet_ids      = module.vpc.private_subnets

#   enable_irsa = true

#   tags = {
#     cluster = "dev"
#   }

#   vpc_id = module.vpc.vpc_id

#   eks_managed_node_group_defaults = {
#     ami_type               = "AL2_x86_64"
#     instance_types         = ["t3.medium"]
#     #vpc_security_group_ids = [aws_security_group.all_worker_mgmt.id]
#   }

#   eks_managed_node_groups = {

#     node_group = {
#       min_size     = 1
#       max_size     = 5
#       desired_size = 1
#     }
#   }
# }
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.29.0"

  cluster_name                   = local.name
  cluster_endpoint_public_access = true

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets

  # EKS Managed Node Group(s)
  eks_managed_node_group_defaults = {
    ami_type       = "AL2_x86_64"
    instance_types = ["t3.medium"]

    attach_cluster_primary_security_group = true
  }

  eks_managed_node_groups = {
    amc-cluster-wg = {
      min_size     = 1
      max_size     = 3
      desired_size = 1

      tags = {
        ExtraTag = "dev"
      }
    }
  }

  tags = local.tags
}

output "update_kubeconfig_command" {
  value = format("%s %s %s %s", "aws eks update-kubeconfig --region", local.region, "--name", module.eks.cluster_name)
}
