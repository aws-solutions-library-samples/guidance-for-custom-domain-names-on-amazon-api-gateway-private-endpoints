resource "aws_kms_key" "route53_logs_cmk" {
  description         = "KMS key for encrypting Route 53 logs in CloudWatch Logs"
  enable_key_rotation = true
  policy = jsonencode({
    Version = "2012-10-17",

    Statement = [
      {
        Effect = "Allow",
        Principal = {
          "AWS" : "arn:${data.aws_partition.current.id}:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        Action   = "kms:*",
        Resource = "*"
      },
      {
        Effect = "Allow",
        Principal = {
          "Service" : "logs.${data.aws_region.current.name}.amazonaws.com"
        },
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource = "*",
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" : "arn:${data.aws_partition.current.id}:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/route53/*"
          }
        }
      }
    ]
  })
}

resource "aws_kms_key" "ecr_repo_cmk" {

  description         = "KMS key for encrypting ecr repository"
  enable_key_rotation = true
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "Enable IAM User Permissions",
        "Effect" : "Allow",
        "Principal" : {
          "AWS" : "arn:${data.aws_partition.current.id}:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        "Action" : "kms:*",
        "Resource" : "*"
      },
      {
        "Sid" : "Allow use of the key",
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "ecr.amazonaws.com"
        },
        "Action" : "kms:Encrypt",
        "Resource" : "*"
      }
    ]
  })

}


resource "aws_kms_key" "ssm_parameter_cmk" {

  description         = "KMS key for encrypting ssm parameters"
  enable_key_rotation = true
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.id}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow use of the key"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.ecs_service.arn
        }
        Action   = "kms:Decrypt"
        Resource = "*"
      }
    ]
  })

}