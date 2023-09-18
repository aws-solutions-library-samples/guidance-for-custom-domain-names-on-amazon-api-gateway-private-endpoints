module "acm" {
  for_each    = local.base_domains
  source      = "git::https://github.com/terraform-aws-modules/terraform-aws-acm.git?ref=27e32f53cd6cbe84287185a37124b24bd7664e03"
  domain_name = "*.${each.value}"
  zone_id     = data.aws_route53_zone.selected[each.value].id
}
