terraform {
  required_version = ">=1.9.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>6.0"
    }
  }
  backend "s3" {
    bucket       = "my-phase-2-learning"
    key          = "k8s-platform/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.aws_Region
}

module "vpc" {
  source = "../modules/vpc"

  vpc_cidr            = "10.1.0.0/16"
  public_subnet_cidrs = ["10.1.1.0/24", "10.1.2.0/24"]
  availability_zones  = ["us-east-1a", "us-east-1b"]
  environment         = "k8s-platform"
}

module "eks" {
  source = "../modules/eks"

  cluster_name       = var.cluster_name
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.public_subnet_ids
  node_instance_type = "t3.small"
  node_desired_size  = 2
}

resource "aws_ecr_repository" "website" {
  name = "learning-website"
}

output "ecr_repository_url" {
  value = aws_ecr_repository.website.repository_url
}
output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}
