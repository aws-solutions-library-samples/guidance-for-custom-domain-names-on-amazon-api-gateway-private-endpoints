module "load_balancer" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-alb?ref=cb8e43d456a863e954f6b97a4a821f41d4280ab8"

  name               = local.name_prefix
  load_balancer_type = var.elb_type == "ALB" ? "application" : "network"
  vpc_id             = data.aws_vpc.selected.id
  internal           = true
  subnets            = local.private_subnets
  security_groups    = var.elb_type == "ALB" ? [local.alb_sg_id] : null
  target_groups = [
    {
      name_prefix      = length(local.name_prefix) > 6 ? substr(local.name_prefix, 0, 6) : local.name_prefix
      backend_protocol = var.elb_type == "ALB" ? "HTTPS" : "TCP"
      backend_port     = "443"
      target_type      = "ip"
      health_check = {
        protocol            = var.elb_type == "ALB" ? "HTTPS" : "TCP"
        healthy_threshold   = 2
        unhealthy_threshold = 2
        interval            = var.elb_type == "ALB" ? 5 : 10
        timeout             = var.elb_type == "ALB" ? 2 : null
      }
    }
  ]
}

resource "aws_lb_listener" "this" {
  #checkov:skip=CKV_AWS_2:protocol is set to HTTPS if ELB is ALB and TLS for NLB
  #checkov:skip=CKV_AWS_103:ssl policy does not allow TLS1.1 this is a false positive
  load_balancer_arn = module.load_balancer.lb_arn
  port              = 443
  protocol          = var.elb_type == "ALB" ? "HTTPS" : "TLS"
  certificate_arn   = module.acm[tolist(local.base_domains)[0]].acm_certificate_arn
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  default_action {
    type             = "forward"
    target_group_arn = module.load_balancer.target_group_arns[0]
  }
}

resource "aws_lb_listener_certificate" "load_balancer" {
  for_each = local.base_domains

  listener_arn    = aws_lb_listener.this.arn
  certificate_arn = module.acm[each.value].acm_certificate_arn
}

resource "aws_security_group" "alb" {
  #checkov:skip=CKV2_AWS_5: Security group is conditionally created and is associated with the ELB if created
  count = var.elb_type == "ALB" && var.external_alb_sg_id == null ? 1 : 0

  name        = "${local.name_prefix}_alb"
  description = "Security Group for ALB"
  vpc_id      = data.aws_vpc.selected.id
  ingress {
    description = "inbound from internet to alb"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description     = "outbound from alb to fargate"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [data.aws_security_group.fg.id]
  }
}

locals {
  alb_sg_id = var.elb_type == "ALB" && var.external_alb_sg_id == null ? aws_security_group.alb[0].id : var.elb_type == "ALB" ? var.external_alb_sg_id : null
}