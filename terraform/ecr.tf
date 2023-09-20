data "aws_ecr_authorization_token" "token" {}

provider "docker" {
  registry_auth {
    address  = "${data.aws_caller_identity.current.id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com"
    username = data.aws_ecr_authorization_token.token.user_name
    password = data.aws_ecr_authorization_token.token.password
  }
}

resource "random_string" "repo_suffix" {
  length  = 5
  special = false
  upper   = false
}

resource "random_string" "image_tag" {
  length  = 5
  special = false
  upper   = false
  keepers = {
    platform   = var.task_platform
    source_img = var.task_image
    source_tag = var.task_image_tag
    dockerfile = filesha256("${path.module}/docker/Dockerfile")
  }
}

resource "aws_ecr_repository" "nginx" {
    #checkov:skip=CKV_AWS_136:Registry is encrypted, customers can create and implement KMS if desired.
  name = "${local.name_prefix}_${random_string.repo_suffix.result}"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  force_delete = true
  encryption_configuration {
    #tfsec:ignore:aws-ecr-repository-customer-key Customers can implement KMS if desired
    encryption_type = "AES256"
  }
}

module "docker_image" {
  source               = "git::https://github.com/terraform-aws-modules/terraform-aws-lambda.git//modules/docker-build?ref=9acd3227087db56abac5f78d1a660b08ee159a9c"
  create_ecr_repo      = false
  ecr_repo             = aws_ecr_repository.nginx.name
  source_path          = "${path.module}/docker"
  image_tag            = random_string.image_tag.result
  build_args = {
    PLATFORM = var.task_platform == "ARM64" ? "linux/arm64" : "linux/amd64"
    IMAGE    = "${var.task_image}:${var.task_image_tag}"
  }
}

resource "aws_ecr_repository_policy" "ecr_policy" {

  repository = aws_ecr_repository.nginx.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Principal = {
          AWS = [
            aws_iam_role.fargate_task.arn
          ]
        }
      }
    ]
  })
}
