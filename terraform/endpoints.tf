locals {
  endpoints = [
    "ecr.dkr",
    "ecr.api",
    "execute-api",
    "logs",
    "s3",
    "ssm",
    var.enable_task_exec ? "ssmmessages" : ""
  ]
  endpoint_ids = {
    "ecr.dkr"     = can(regex("(vpce-)[a-z0-9].*", data.external.existing_endpoint["ecr.dkr"].result)) ? null : true
    "ecr.api"     = can(regex("(vpce-)[a-z0-9].*", data.external.existing_endpoint["ecr.api"].result)) ? null : true
    "execute-api" = can(regex("(vpce-)[a-z0-9].*", data.external.existing_endpoint["execute-api"].result)) ? null : true
    "logs"        = can(regex("(vpce-)[a-z0-9].*", data.external.existing_endpoint["logs"].result)) ? null : true
    "s3"          = can(regex("(vpce-)[a-z0-9].*", data.external.existing_endpoint["s3"].result)) ? null : true
    "ssm"         = can(regex("(vpce-)[a-z0-9].*", data.external.existing_endpoint["ssm"].result)) ? null : true
    "ssmmessages" = var.enable_task_exec ? can(regex("(vpce-)[a-z0-9].*", data.external.existing_endpoint["ssmmessages"].result)) ? null : true : null
  }
}

data "external" "existing_endpoint" {
  for_each = { for endpoint in local.endpoints : endpoint => {
    endpoint = endpoint
    vpc_id   = data.aws_vpc.selected.id
    }
  }

  program = ["/bin/bash", "${path.module}/scripts/existing_endpoint.sh", each.value.endpoint, each.value.vpc_id]
}

data "aws_route_tables" "selected" {
  vpc_id = data.aws_vpc.selected.id
}

module "endpoints" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc//modules/vpc-endpoints?ref=c467edb180c38f493b0e9c6fdc22998a97dfde89"

  security_group_ids = [data.aws_security_group.endpoints.id]
  subnet_ids         = local.private_subnets
  vpc_id             = data.aws_vpc.selected.id
  endpoints = { for endpoint in local.endpoints : endpoint => {

    create              = lookup(local.endpoint_ids, endpoint, false)
    service             = endpoint
    private_dns_enabled = endpoint != "s3" ? true : null
    service_type        = endpoint == "s3" ? "Gateway" : "Interface"
    route_table_ids     = endpoint == "s3" ? data.aws_route_tables.selected.ids : null
    }
  }
}


resource "aws_security_group" "vpc_endpoints" {
  count = var.external_endpoint_sg_id == null ? 1 : 0
  #checkov:skip=CKV2_AWS_5:Security groups are attached conditionally if an external security group is not provided
  name        = "${local.name_prefix}_vpc_endpoints"
  description = "Ingress to Service Endpoints"
  vpc_id      = local.vpc_id
  ingress {
    description = "HTTPS Ingress from VPC"
    from_port   = "443"
    to_port     = "443"
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }
}

data "aws_security_group" "endpoints" {
  id = var.external_endpoint_sg_id != null ? var.external_endpoint_sg_id : aws_security_group.vpc_endpoints[0].id
}