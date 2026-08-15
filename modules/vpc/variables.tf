variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets"
  type        = list(string)
}

variable "availability_zones" {
  description = "List of AZs to spread subnets across"
  type        = list(string)
}

variable "environment" {
  description = "Environment name, used in tags (e.g. website, backend)"
  type        = string
}
