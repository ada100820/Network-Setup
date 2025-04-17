###########################
# -------- GLOBAL ---------
###########################
variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "environment" {
  description = "Deployment environment: stage | prod"
  type        = string
}

###########################
# -------- VPC ------------
###########################
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.100.0.0/16"
}

variable "azs" {
  description = "AZs to span (must match subnet CIDR list lengths)"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDRs for public subnets, one per AZ"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDRs for private subnets, one per AZ"
  type        = list(string)
}

###########################
# -------- SECURITY -------
###########################
variable "bastion_cidr" {
  description = "Trusted CIDR allowed to SSH (22/tcp) into the bastion"
  type        = string
  default     = "203.0.113.5/32"
}
