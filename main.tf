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

locals {
  region        = "ap-south-2"
  name          = "aws-eks"
  max_node_size = 2
  min_node_size = 1
}

provider "aws" {
  region = local.region
}

# VPC
resource "aws_vpc" "eks_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name}-vpc"
  }
}

# Availability Zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Private Subnets
resource "aws_subnet" "eks_private" {
  count                   = 3
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.eks_vpc.cidr_block, 3, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name}-private-${count.index + 1}"
  }
}

# Public Subnets
resource "aws_subnet" "eks_public" {
  count                   = 3
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.eks_vpc.cidr_block, 3, count.index + 3)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name}-public-${count.index + 1}"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "eks_igw" {
  vpc_id = aws_vpc.eks_vpc.id

  tags = {
    Name = "${local.name}-igw"
  }
}

# Route Table for Public Subnets
resource "aws_route_table" "eks_public_rt" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks_igw.id
  }

  tags = {
    Name = "${local.name}-public-rt"
  }
}

# Associate Public Subnets with Public Route Table
resource "aws_route_table_association" "eks_public_rt_assoc" {
  count          = 3
  subnet_id      = aws_subnet.eks_public[count.index].id
  route_table_id = aws_route_table.eks_public_rt.id
}

# Allocate EIPs for NAT Gateways
resource "aws_eip" "eks_eip" {  
  domain = "vpc"

  tags = {
    Name = "${local.name}-eip"
  }
}

# NAT Gateways
resource "aws_nat_gateway" "eks_nat_gateway" {
  
  allocation_id = aws_eip.eks_eip.id
  subnet_id     = aws_subnet.eks_public[0].id

  tags = {
    Name = "${local.name}-nat-gateway"
  }
}

# Route Table for Private Subnets
resource "aws_route_table" "eks_private_rt" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.eks_nat_gateway.id
  }

  tags = {
    Name = "${local.name}-private-rt"
  }

}

# Associate Private Subnets with Private Route Table
resource "aws_route_table_association" "eks_private_rt_assoc" {
  count          = 3
  subnet_id      = aws_subnet.eks_private[count.index].id
  route_table_id = aws_route_table.eks_private_rt.id
}

resource "aws_iam_role" "eks_cluster_role" {
  name = "${local.name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "eks.amazonaws.com" }
      }
    ]
  })

  tags = {
    Name = "${local.name}-cluster-role"
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_service_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}


resource "aws_iam_role" "eks_node_role" {
  name = "${local.name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
      }
    ]
  })

  tags = {
    Name = "${local.name}-node-role"
  }
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "ec2_container_registry_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}


resource "aws_security_group" "eks_cluster_sg" {
  name_prefix = "${local.name}-cluster-sg-"
  vpc_id      = aws_vpc.eks_vpc.id

  ingress {
    description     = "Allow all traffic from nodes"
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.eks_node_sg.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-cluster-sg"
  }
}

resource "aws_security_group" "eks_node_sg" {
  name_prefix = "${local.name}-node-sg-"
  vpc_id      = aws_vpc.eks_vpc.id

  ingress {
    description = "Allow worker node communication with cluster control plane"
    from_port   = 1025
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow all pods to communicate with each other"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-node-sg"
  }
}

resource "aws_security_group" "eks_app_sg" {
  name_prefix = "${local.name}-app-sg-"
  vpc_id      = aws_vpc.eks_vpc.id

  ingress {
    description = "Allow HTTP traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-app-sg"
  }
}


resource "aws_eks_cluster" "eks_cluster" {
  name     = "${local.name}-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids = concat(
      aws_subnet.eks_private[*].id,
      aws_subnet.eks_public[*].id
    )
    security_group_ids = [aws_security_group.eks_cluster_sg.id]
  }

  tags = {
    Name = "${local.name}-cluster"
  }
}

# RSA KEY PAIR
resource "tls_private_key" "foo" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_key_pair" "foo" {
  key_name   = "${local.name}_id_rsa"
  public_key = tls_private_key.foo.public_key_openssh
}

output "ssh_key" {
  value     = tls_private_key.foo.private_key_pem
  sensitive = true
}

resource "aws_eks_node_group" "eks_nodes" {
  
  depends_on = [ 
      aws_subnet.eks_private, 
      aws_route_table.eks_private_rt,
      aws_route_table_association.eks_private_rt_assoc
  ]

  cluster_name  = aws_eks_cluster.eks_cluster.name
  
  node_role_arn = aws_iam_role.eks_node_role.arn
  
  subnet_ids    = aws_subnet.eks_private[*].id
  
  scaling_config {
    desired_size = 1
    max_size     = local.max_node_size
    min_size     = local.min_node_size
  }

  instance_types = ["t3.medium"]

  remote_access {
    ec2_ssh_key               = aws_key_pair.foo.key_name
    source_security_group_ids = [aws_security_group.eks_node_sg.id]
  }

  tags = {
    Name = "${local.name}-node-group"
  }
}

output "cluster_name" {
  value = aws_eks_cluster.eks_cluster.name
}

output "kubeconfig_endpoint" {
  value = aws_eks_cluster.eks_cluster.endpoint
}

output "cluster_role" {
  value = aws_iam_role.eks_cluster_role.arn
}

output "kubeconfig" {
  value = <<EOT
    apiVersion: v1
    kind: Config
    clusters:
    - cluster:
        server: ${aws_eks_cluster.eks_cluster.endpoint}
        certificate-authority-data: ${aws_eks_cluster.eks_cluster.certificate_authority[0].data}
      name: eks-cluster
    contexts:
    - context:
        cluster: eks-cluster
        user: eks-user
      name: eks-context
    current-context: eks-context
    users:
    - name: eks-user
      user:
        exec:
          apiVersion: client.authentication.k8s.io/v1
          command: aws
          args:
          - "eks"
          - "get-token"
          - "--region"
          - "eu-north-1"
          - "--cluster-name"
          - "${aws_eks_cluster.eks_cluster.name}"
          interactiveMode: "Never"
  EOT
}