data "aws_route53_zone" "selected" {
  for_each = local.base_domains
  name     = each.value

  private_zone = false
}

resource "aws_route53_record" "api" {
  for_each = { for api in local.api_list : api.CUSTOM_DOMAIN_URL => api }

  allow_overwrite = true
  name            = each.value.CUSTOM_DOMAIN_URL
  records         = [module.load_balancer.lb_dns_name]
  ttl             = 60
  type            = "CNAME"
  zone_id         = aws_route53_zone.private[trimprefix(regex("\\..*$", each.value.CUSTOM_DOMAIN_URL), ".")].zone_id
}

resource "aws_route53_zone" "private" {
  for_each = local.base_domains
  name     = each.value
  vpc {
    vpc_id = local.vpc_id
  }
}

resource "aws_kms_key" "private" {
  customer_master_key_spec = "ECC_NIST_P256"
  deletion_window_in_days  = 7
  key_usage                = "SIGN_VERIFY"
  policy = jsonencode({
    Statement = [
      {
        Action = [
          "kms:DescribeKey",
          "kms:GetPublicKey",
          "kms:Sign",
          "kms:Verify",
        ],
        Effect = "Allow"
        Principal = {
          Service = "dnssec-route53.amazonaws.com"
        }
        Resource = "*"
        Sid      = "Allow Route 53 DNSSEC Service",
      },
      {
        Action = "kms:*"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Resource = "*"
        Sid      = "Enable IAM User Permissions"
      },
    ]
    Version = "2012-10-17"
  })
}

resource "aws_route53_key_signing_key" "private" {
  for_each = aws_route53_zone.private
  hosted_zone_id             = aws_route53_zone.private[each.key].id
  key_management_service_arn = aws_kms_key.private.arn
  name                       = "${local.name_prefix}-private-route53"
}

resource "aws_route53_hosted_zone_dnssec" "private" {
  depends_on = [
    aws_route53_key_signing_key.private
  ]
  for_each = aws_route53_zone.private
  hosted_zone_id = aws_route53_key_signing_key.private[each.key].hosted_zone_id
}

resource "aws_cloudwatch_log_group" "aws_route53_private" {
  for_each = local.base_domains

  name              = "/aws/route53/${each.value}"
  retention_in_days = 30
}

# Example CloudWatch log resource policy to allow Route53 to write logs
# to any log group under /aws/route53/*

data "aws_iam_policy_document" "route53-query-logging-policy" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["arn:aws:logs:*:*:log-group:/aws/route53/*"]

    principals {
      identifiers = ["route53.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "route53-query-logging-policy" {
  policy_document = data.aws_iam_policy_document.route53-query-logging-policy.json
  policy_name     = "route53-query-logging-policy"
}