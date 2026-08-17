variable "aws_Region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "learning-cluster"
}

variable "ecr_repo_name" {
  description = "ECR repository name"
  type        = string
  default     = "learning-website"
}
