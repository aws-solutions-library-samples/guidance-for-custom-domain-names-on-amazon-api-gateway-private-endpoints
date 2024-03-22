resource "aws_security_group" "fg" {
  count = var.external_fargate_sg_id == null ? 1 : 0
  #checkov:skip=CKV2_AWS_5:Security groups are attached conditionally if an external security group is not provided
  name        = "${local.name_prefix}_fg"
  vpc_id      = data.aws_vpc.selected.id
  description = "Egress from Fargate"
  egress {
    description     = "HTTPS to Service Endpoints"
    from_port       = "443"
    to_port         = "443"
    protocol        = "tcp"
    security_groups = [data.aws_security_group.endpoints.id]
  }
  egress {
    description     = "HTTPS to S3 Gateway Endpoint"
    from_port       = "443"
    to_port         = "443"
    protocol        = "tcp"
    prefix_list_ids = [data.aws_prefix_list.s3.id]
  }
}

data "aws_security_group" "fg" {
  id = var.external_fargate_sg_id != null ? var.external_fargate_sg_id : aws_security_group.fg[0].id
}

data "aws_vpc_endpoint_service" "s3" {
  service      = "s3"
  service_type = "Gateway"
}

data "aws_prefix_list" "s3" {
  filter {
    name   = "prefix-list-name"
    values = [data.aws_vpc_endpoint_service.s3.service_name]
  }
}

resource "aws_security_group_rule" "fg_ingress" {
  type              = "ingress"
  description       = "Ingress to Fargate"
  security_group_id = data.aws_security_group.fg.id
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"

  source_security_group_id = var.elb_type == "ALB" ? local.alb_sg_id : null
  cidr_blocks              = var.elb_type == "NLB" ? ["0.0.0.0/0"] : null #tfsec:ignore:aws-ec2-no-public-ingress-sgr #exposure required for ingress on NLB
}

module "ecs" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-ecs?ref=32f1169f8fd2f1beb224a0b0f040d8825eb01c05"

  cluster_name = local.name_prefix
  cluster_settings = {
    name  = "containerInsights"
    value = "enabled"
  }
  fargate_capacity_providers = {
    FARGATE = {
      default_capacity_provider_strategy = {
        weight = 100
      }
    }
  }
}

resource "null_resource" "proxy_config" {
  triggers = {
    config_sha1 = sha1(file("${path.module}/../config/proxy-config.yaml"))
  }
}

resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = var.task_scale_max
  min_capacity       = var.task_scale_min
  resource_id        = "service/${module.ecs.cluster_name}/${aws_ecs_service.nginx.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "ecs_policy" {
  name               = local.name_prefix
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = var.task_scale_cpu_pct
    scale_in_cooldown  = 60
    scale_out_cooldown = 60
  }
}

resource "random_id" "nginx_config" {
  byte_length = 8
}

resource "aws_ssm_parameter" "nginx_config" {
  name   = "nginx-conf-${random_id.nginx_config.id}"
  key_id = aws_kms_key.ssm_parameter_cmk.arn
  type   = "SecureString"
  value = templatefile(
    "${path.module}/template_files/nginx.conf.tftpl", {
      apis = zipmap(
        [for api in local.api_list : trimprefix(api.CUSTOM_DOMAIN_URL, "https://")],
        [for api in local.api_list : trimprefix(api.PRIVATE_API_URL, "https://")]
      ), dns_server = cidrhost(data.aws_vpc.selected.cidr_block, 2, ),
      endpoint_url  = module.endpoints.endpoints["execute-api"].dns_entry[0].dns_name
    }
  )
}

resource "aws_ecs_task_definition" "app" {
  family                   = local.service_name
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  requires_compatibilities = ["FARGATE"]
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.task_platform
  }
  container_definitions = jsonencode(
    [{
      cpu                  = 512
      image                = docker_registry_image.nginx.name
      memory               = 1024
      name                 = local.service_name
      essential            = true
      initProcessesEnabled = true
      healthcheck = {
        command  = ["CMD-SHELL", "curl --cacert /cert.pem https://localhost || exit 1"]
        interval = 30
        retries  = 3
        timeout  = 5
      }
      mountPoints = []
      volumesFrom = []
      networkMode = "awsvpc"
      secrets = [
        {
          name      = "NGINX_CONFIG",
          valueFrom = aws_ssm_parameter.nginx_config.arn
        }
      ]
      portMappings = [
        {
          protocol      = "tcp"
          containerPort = 443
          hostPort      = 443
        }
      ]
      logConfiguration = {
        logdriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${local.service_name}-${random_id.id.hex}"
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "stdout"
          "awslogs-create-group"  = "true"
        }
      }
    }]
  )
  execution_role_arn = aws_iam_role.ecs_service.arn
  task_role_arn      = aws_iam_role.fargate_task.arn
  lifecycle {
    replace_triggered_by = [
      null_resource.proxy_config.id
    ]
  }
}

resource "aws_ecs_service" "nginx" {
  depends_on = [
    module.vpc[0],
    module.load_balancer
  ]

  name                   = local.service_name
  cluster                = module.ecs.cluster_id
  task_definition        = aws_ecs_task_definition.app.arn
  launch_type            = "FARGATE"
  scheduling_strategy    = "REPLICA"
  desired_count          = 1
  force_new_deployment   = true
  enable_execute_command = var.enable_task_exec
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = local.private_subnets
    assign_public_ip = false
    security_groups  = [data.aws_security_group.fg.id]
  }

  load_balancer {
    target_group_arn = module.load_balancer.target_group_arns[0]
    container_name   = local.service_name
    container_port   = 443
  }
}
