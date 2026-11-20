mock_provider "aws" {}

variables {
  public_route_table_id = "rtb-0123456789abcdef0"
  subnet_cidr_block     = "10.0.10.0/24"
}

override_data {
  target = data.aws_ssm_parameter.amazon_linux
  values = { value = "ami-0123456789abcdef0" }
}

run "uses_existing_public_routing" {
  command = plan

  override_data {
    target = data.aws_route_table.public
    values = {
      id     = "rtb-0123456789abcdef0"
      vpc_id = "vpc-0123456789abcdef0"
      routes = [{
        cidr_block = "0.0.0.0/0"
        gateway_id = "igw-0123456789abcdef0"
      }]
    }
  }

  assert {
    condition = (
      aws_subnet.web.vpc_id == data.aws_route_table.public.vpc_id &&
      aws_security_group.web.vpc_id == data.aws_route_table.public.vpc_id &&
      aws_route_table_association.web.route_table_id == var.public_route_table_id
    )
    error_message = "The new subnet and security group must use the existing route table's VPC, and the subnet must be associated with that route table."
  }
}

run "rejects_private_default_route" {
  command = plan

  override_data {
    target = data.aws_route_table.public
    values = {
      id     = "rtb-0123456789abcdef0"
      vpc_id = "vpc-0123456789abcdef0"
      routes = [{
        cidr_block     = "0.0.0.0/0"
        gateway_id     = null
        nat_gateway_id = "nat-0123456789abcdef0"
      }]
    }
  }

  expect_failures = [aws_route_table_association.web]
}
