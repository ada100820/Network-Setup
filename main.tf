###########################
# -------- VPC ------------
###########################
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name        = "${var.environment}-vpc"
    Environment = var.environment
  }
}

###########################
# IGW
###########################
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.environment}-igw", Environment = var.environment }
}

###########################
# PUBLIC SUBNETS
###########################
resource "aws_subnet" "public" {
  for_each                = { for idx, cidr in var.public_subnet_cidrs : idx => cidr }
  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  availability_zone       = var.azs[tonumber(each.key)]
  map_public_ip_on_launch = true
  tags = {
    Name        = "${var.environment}-public-${each.key}"
    Environment = var.environment
    Tier        = "public"
  }
}

###########################
# PRIVATE SUBNETS
###########################
resource "aws_subnet" "private" {
  for_each                = { for idx, cidr in var.private_subnet_cidrs : idx => cidr }
  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  availability_zone       = var.azs[tonumber(each.key)]
  map_public_ip_on_launch = false
  tags = {
    Name        = "${var.environment}-private-${each.key}"
    Environment = var.environment
    Tier        = "private"
  }
}

###########################
# NAT (single, cost‑effective)
###########################
resource "aws_eip" "nat" {
  vpc  = true
  tags = { Name = "${var.environment}-nat-eip" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = values(aws_subnet.public)[0].id
  tags          = { Name = "${var.environment}-nat", Environment = var.environment }
}

###########################
# ROUTE TABLES
###########################
# Public
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.environment}-public-rt", Environment = var.environment }
}

resource "aws_route" "public_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# Private
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.environment}-private-rt", Environment = var.environment }
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

###########################
# SECURITY GROUPS
###########################
resource "aws_security_group" "bastion" {
  name        = "${var.environment}-bastion-sg"
  description = "SSH jump host"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from trusted network"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.bastion_cidr]
  }

  egress { from_port = 0 to_port = 0 protocol = "-1" cidr_blocks = ["0.0.0.0/0"] }

  tags = { Name = "${var.environment}-bastion-sg", Environment = var.environment }
}

resource "aws_security_group" "web" {
  name        = "${var.environment}-web-sg"
  description = "Public‑facing web tier"
  vpc_id      = aws_vpc.main.id

  ingress { from_port = 80  to_port = 80  protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] }
  ingress { from_port = 443 to_port = 443 protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] }
  ingress {
    description     = "SSH via bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress { from_port = 0 to_port = 0 protocol = "-1" cidr_blocks = ["0.0.0.0/0"] }

  tags = { Name = "${var.environment}-web-sg", Environment = var.environment }
}

resource "aws_security_group" "app" {
  name        = "${var.environment}-app-sg"
  description = "Backend/microservices tier"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Traffic from web tier"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }
  ingress {
    description     = "SSH via bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress { from_port = 0 to_port = 0 protocol = "-1" cidr_blocks = ["0.0.0.0/0"] }

  tags = { Name = "${var.environment}-app-sg", Environment = var.environment }
}

###########################
# NETWORK ACL (audit rules)
###########################
resource "aws_network_acl" "env" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.environment}-nacl", Environment = var.environment }
}

# Associate NACL with all subnets
resource "aws_network_acl_association" "assoc_public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  network_acl_id = aws_network_acl.env.id
}

resource "aws_network_acl_association" "assoc_private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  network_acl_id = aws_network_acl.env.id
}

# -------- Inbound --------
resource "aws_network_acl_rule" "in_ssh" {
  network_acl_id = aws_network_acl.env.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.bastion_cidr
  from_port      = 22
  to_port        = 22
}

resource "aws_network_acl_rule" "in_http" {
  network_acl_id = aws_network_acl.env.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 80
  to_port        = 80
}

resource "aws_network_acl_rule" "in_https" {
  network_acl_id = aws_network_acl.env.id
  rule_number    = 120
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "in_ephemeral" {
  network_acl_id = aws_network_acl.env.id
  rule_number    = 130
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

# -------- Outbound --------
resource "aws_network_acl_rule" "out_https" {
  network_acl_id = aws_network_acl.env.id
  rule_number    = 100
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "out_http" {
  network_acl_id = aws_network_acl.env.id
  rule_number    = 110
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 80
  to_port        = 80
}

resource "aws_network_acl_rule" "out_ephemeral" {
  network_acl_id = aws_network_acl.env.id
  rule_number    = 120
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}
