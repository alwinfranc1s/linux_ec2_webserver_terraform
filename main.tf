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
  default     = "ap-south-1"
}

variable "public_route_table_id" {
  description = "ID of the approved existing public route table. Its VPC hosts the new subnet."
  type        = string
}

variable "subnet_cidr_block" {
  description = "Unused IPv4 CIDR within the existing VPC, approved for the new subnet."
  type        = string
}

provider "aws" {
  region = var.aws_region
}

data "aws_ssm_parameter" "amazon_linux" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_route_table" "public" {
  route_table_id = var.public_route_table_id
}

resource "aws_subnet" "web" {
  vpc_id     = data.aws_route_table.public.vpc_id
  cidr_block = var.subnet_cidr_block

  tags = { Name = "terraform-web-public-subnet" }
}

resource "aws_route_table_association" "web" {
  subnet_id      = aws_subnet.web.id
  route_table_id = data.aws_route_table.public.id

  lifecycle {
    precondition {
      condition = anytrue([
        for route in data.aws_route_table.public.routes :
        route.cidr_block == "0.0.0.0/0" && try(startswith(route.gateway_id, "igw-"), false)
      ])
      error_message = "The existing route table must have an IPv4 default route (0.0.0.0/0) to an internet gateway."
    }
  }
}

resource "aws_security_group" "web" {
  name        = "terraform-web-http"
  description = "Allow public HTTP and outbound HTTPS for package downloads"
  vpc_id      = data.aws_route_table.public.vpc_id

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
