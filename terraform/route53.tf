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
  zone_id         = aws_route53_zone.this[trimprefix(regex("\\..*$", each.value.CUSTOM_DOMAIN_URL), ".")].zone_id
}

resource "aws_route53_zone" "this" {
  for_each = local.base_domains
  #checkov:skip=CKV2_AWS_39:Query logging enabled using aws_route53_query_log resources seperatly
  #checkov:skip=CKV2_AWS_38:DNSSEC enabled with aws_route53_signing_key resources seperatly
  name = each.value
  vpc {
    vpc_id = local.vpc_id
  }
}

resource "aws_route53_signing_key" "this" {
  for_each = local.base_domains
  
  hosted_zone_id = aws_route53_zone.this[each.value].zone_id 
  key_management_service_arn = aws_kms_key.route53_signing_key_cmk.arn
  name = "${local.name_prefix}-${each.value}"
}

resource "aws_cloudwatch_log_group" "this" {
  for_each          = local.base_domains
  kms_key_id = aws_kms_key.route53_logs_cmk.arn
  name_prefix       = "/aws/route53/${each.value}"
  retention_in_days = 365
}

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
  policy_name     = "${local.name_prefix}-route53-query-logging-policy"
}

resource "aws_route53_query_log" "this" {
  for_each                 = local.base_domains
  zone_id                  = data.aws_route53_zone.selected[each.value].zone_id
  cloudwatch_log_group_arn = aws_cloudwatch_log_group.this[each.value].arn
}