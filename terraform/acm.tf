module "acm" {
  for_each          = local.base_domains
  source            = "git::https://github.com/terraform-aws-modules/terraform-aws-acm?ref=8d0b22f1f242a1b36e29b8cb38aaeac9b887500d"
  domain_name       = "*.${each.value}"
  zone_id           = data.aws_route53_zone.selected[each.value].id
  validation_method = "DNS"
}
