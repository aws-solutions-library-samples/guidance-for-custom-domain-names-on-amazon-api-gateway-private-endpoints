data "aws_ecr_authorization_token" "token" {}

provider "docker" {
  registry_auth {
    address  = "${data.aws_caller_identity.current.id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com"
    username = data.aws_ecr_authorization_token.token.user_name
    password = data.aws_ecr_authorization_token.token.password
  }
}


resource "random_id" "image_tag" {
  byte_length = 2
  keepers = {
    platform    = var.task_platform
    source_img  = var.task_image
    source_tag  = var.task_image_tag
    dockerfile  = filesha256("${path.module}/docker/Dockerfile")
    entrypoint  = filesha256("${path.module}/docker/entrypoint.sh")
    openssl_cnf = filesha256("${path.module}/docker/openssl.cnf")
  }
}

#tfsec:ignore:aws-ecr-repository-customer-key #Repository is encrypted, customers can deploy customer managed keys if desired.
resource "aws_ecr_repository" "nginx" {
  name                 = "${local.name_prefix}-${random_id.id.hex}"
  force_delete         = true
  image_tag_mutability = "IMMUTABLE"
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr_repo_cmk.arn
  }
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "nginx" {
  repository = aws_ecr_repository.nginx.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1,
        description  = "Expire tagged images older than 300 days",
        selection = {
          tagStatus   = "tagged",
          tagPrefixList = ["nginx"],
          countType   = "sinceImagePushed",
          countUnit   = "days",
          countNumber = 300
        },
        action = {
          type = "expire"
        }
      },
            {
        rulePriority = 2,
        description  = "Expire untagged images older than 10 days",
        selection = {
          tagStatus   = "untagged",
          countType   = "sinceImagePushed",
          countUnit   = "days",
          countNumber = 10
        },
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 3,
        description  = "Keep last 30 images",
        selection = {
          tagStatus   = "any",
          countType   = "imageCountMoreThan",
          countNumber = 30
        },
        action = {
          type = "expire"
        }
      }
    ]
  })

}

resource "docker_image" "nginx" {
  name = "${aws_ecr_repository.nginx.repository_url}:${random_id.image_tag.hex}"
  build {
    context = "${path.module}/docker"
    build_args = {
      PLATFORM = var.task_platform == "ARM64" ? "linux/arm64" : "linux/amd64"
      IMAGE    = "${var.task_image}:${var.task_image_tag}"
    }
    force_remove = true
  }
}

resource "docker_registry_image" "nginx" {
  name                 = docker_image.nginx.name
  insecure_skip_verify = true
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
