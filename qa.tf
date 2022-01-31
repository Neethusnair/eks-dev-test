terraform {

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.20.0"
    }
  }

  backend "remote" {
    organization = "SREYO"

    workspaces {
      name = "qa-aws-cluster"
    }
  }

}

variable "region" {
  default     = "us-east-2"
  description = "AWS region"
}

variable "cluster_name1" {
  description = "name"
}

provider "aws" {
  region = var.region

}

data "aws_eks_cluster" "cluster1" {
  name = module.eks1.cluster_id
}

data "aws_eks_cluster_auth" "cluster1" {
  name = module.eks1.cluster_id
}

data "aws_availability_zones" "available" {
}



resource "aws_security_group" "worker_group_mgmt_two" {
  name_prefix = "worker_group_mgmt_two"
  vpc_id      = module.vpc1.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
      "10.0.0.0/8",
    ]
  }
}

resource "aws_security_group" "all_worker_mgmt" {
  name_prefix = "all_worker_management"
  vpc_id      = module.vpc1.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
      "10.0.0.0/8",
      "172.16.0.0/12",
      "192.168.0.0/16",
    ]
  }
}

module "vpc1" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.2.0"

  name = "${var.cluster_name1}-vpc"
  cidr = "10.0.0.0/16"
  //azs                  = data.aws_availability_zones.available.names
  azs = ["us-east-2a", "us-east-2b"]
  //private_subnets      = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  //public_subnets       = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  private_subnets      = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets       = ["10.0.4.0/24", "10.0.5.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name1}" = "shared"
    "kubernetes.io/role/elb"                     = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name1}" = "shared"
    "kubernetes.io/role/internal-elb"            = "1"
  }
}

module "eks1" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "17.24.0"
  cluster_name    = var.cluster_name1
  cluster_version = "1.20"
  subnets         = module.vpc1.private_subnets

  vpc_id = module.vpc1.vpc_id

  worker_groups = [
    {
      name                          = "worker-group-2"
      instance_type                 = "t2.small"
      additional_userdata           = "echo foo bar"
      asg_desired_capacity          = 1
      additional_security_group_ids = [aws_security_group.worker_group_mgmt_two.id]
    },
  ]

  worker_additional_security_group_ids = [aws_security_group.all_worker_mgmt.id]
}



provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster1.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster1.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster1.token
  #load_config_file       = false
  #version                = "~> 1.12"
}