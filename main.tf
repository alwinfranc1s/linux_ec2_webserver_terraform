terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.73.0"
    }
  }
}

variable "aws_region" {
  description = "AWS region to deploy the web server in."
  type        = string
  default     = "us-east-1"
}

provider "aws" {
  region = var.aws_region
}

data "aws_ssm_parameter" "amazon_linux" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_vpc" "web" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "terraform-web-vpc" }
}

resource "aws_subnet" "web" {
  vpc_id     = aws_vpc.web.id
  cidr_block = "10.0.1.0/24"

  tags = { Name = "terraform-web-public-subnet" }
}

resource "aws_internet_gateway" "web" {
  vpc_id = aws_vpc.web.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.web.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.web.id
  }
}

resource "aws_route_table_association" "web" {
  subnet_id      = aws_subnet.web.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web" {
  name        = "terraform-web-http"
  description = "Allow public HTTP and outbound HTTPS for package downloads"
  vpc_id      = aws_vpc.web.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "web" {
  ami                         = data.aws_ssm_parameter.amazon_linux.value
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.web.id
  vpc_security_group_ids      = [aws_security_group.web.id]
  associate_public_ip_address = true
  user_data                   = file("${path.module}/user_data.sh")
  user_data_replace_on_change = true

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    encrypted = true
  }

  depends_on = [aws_route_table_association.web]

  tags = { Name = "terraform-web-server" }
}

output "web_url" {
  description = "Public HTTP URL for the demo page."
  value       = "http://${aws_instance.web.public_ip}/"
}
