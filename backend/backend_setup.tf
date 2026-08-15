terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>6.0"
    }
  }
}

module "vpc" {
  source = "../modules/vpc"

  vpc_cidr            = "10.0.0.0/16"
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
  availability_zones  = ["us-east-1a", "us-east-1b"]
  environment         = "backend"
}

#1. create a s3 bucket
resource "aws_s3_bucket" "terraform_state" {
  bucket = "my-phase-2-learning"

  lifecycle {
    prevent_destroy = true
  }
}

#2. Enable versioining for rollback in case of corruption
resource "aws_s3_bucket_versioning" "state_versioning" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

#3. Encrypt the state bucket so secrets inside the state are secure
resource "aws_s3_bucket_server_side_encryption_configuration" "state_encyrption" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

#4. block all public access
resource "aws_s3_bucket_public_access_block" "state_public_block" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#5. Dynamo table for state locking
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-state-looking"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

