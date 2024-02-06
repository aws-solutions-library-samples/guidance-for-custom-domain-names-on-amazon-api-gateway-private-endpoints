data "aws_iam_policy" "ecs" {
  name = "AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_service" {
  name = "${local.name_prefix}_ecs_${random_id.id.hex}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = [
            "ecs-tasks.amazonaws.com"
          ]
        }
      },
    ]
  })
}

resource "aws_iam_role" "fargate_task" {
  name = "${local.name_prefix}_fargate_${random_id.id.hex}"
  assume_role_policy = jsonencode(
    {
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = "sts:AssumeRole"
          Principal = {
            Service = [
              "ecs-tasks.amazonaws.com"
            ]
          }
        }
      ]
    }
  )
}

resource "aws_iam_policy" "ecs_service" {
  name = "${local.name_prefix}_ecs_${random_id.id.hex}"
  policy = jsonencode(
    {
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "logs:CreateLogGroup"
          ]
          Resource = "arn:${data.aws_partition.current.id}:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/${local.service_name}-${random_id.id.hex}:*"
        },
        {
          Effect = "Allow"
          Action = [
            "ssm:GetParameters"
          ]
          Resource = aws_ssm_parameter.nginx_config.arn
        }
      ]
    }
  )
}

resource "aws_iam_policy" "fargate_task" {
  name = "${local.name_prefix}_fargate_${random_id.id.hex}"
  policy = jsonencode(
    {
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "s3:GetObject"
          ]
          Resource = "arn:aws:s3:::prod-${data.aws_region.current.name}-starport-layer-bucket/*"
        }
      ]
    }
  )
}

resource "aws_iam_role_policy_attachment" "ecs_service_managed_policy" {
  role       = aws_iam_role.ecs_service.name
  policy_arn = data.aws_iam_policy.ecs.arn
}

resource "aws_iam_role_policy_attachment" "ecs_service" {
  role       = aws_iam_role.ecs_service.name
  policy_arn = aws_iam_policy.ecs_service.arn
}

resource "aws_iam_role_policy_attachment" "fargate_task_managed_policy" {
  role       = aws_iam_role.fargate_task.name
  policy_arn = data.aws_iam_policy.ecs.arn
}

resource "aws_iam_role_policy_attachment" "fargate_task" {
  role       = aws_iam_role.fargate_task.name
  policy_arn = aws_iam_policy.fargate_task.arn
}

data "aws_iam_policy_document" "nlb_access_log_policy" {
  statement {
    sid    = "AWSLogDeliveryAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [module.elb_bucket.s3_bucket_arn]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
  statement {
    sid    = "AWSLogDeliveryWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${module.elb_bucket.s3_bucket_arn}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.id}:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:*"]
    }

  }
}

data "aws_iam_policy_document" "alb_access_log_policy" {
  statement {
    sid       = "AWSLogDelivery"
    effect    = "Allow"
    actions   = ["s3:PubObject"]
    resources = ["${module.elb_bucket.s3_bucket_arn}/*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.id}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}