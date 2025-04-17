output "vpc_id" {
  description = "ID of the newly created VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = [for s in aws_subnet.private : s.id]
}

output "security_group_ids" {
  description = "Key SGs for this environment"
  value = {
    bastion = aws_security_group.bastion.id
    web     = aws_security_group.web.id
    app     = aws_security_group.app.id
  }
}
