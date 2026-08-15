variable "aws_Region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "Globally unique S2 bucket name"
  type        = string
  default     = "my-learning-bucket-terraform"
}

variable "aws_access_key" {
  description = "access key to login to the AWS username"
  type        = string
  sensitive   = true
}

variable "aws_secret_key" {
  description = "secret key to login to the AWS IAM"
  type        = string
  sensitive   = true
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}
