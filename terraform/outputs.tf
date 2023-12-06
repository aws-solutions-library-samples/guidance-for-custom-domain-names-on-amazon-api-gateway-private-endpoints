data "aws_iam_policy_document" "this" {
  for_each = { for api in local.api_list : api.CUSTOM_DOMAIN_URL => {
    api_stage     = split("/", api.PRIVATE_API_URL)[3],
    resource_path = can(split(regex("(https://(.*/){2})", api.PRIVATE_API_URL), api.PRIVATE_API_URL)[1]) ? split(regex("(https://(.*/){2})", api.PRIVATE_API_URL), api.PRIVATE_API_URL)[1] : "*",
    verbs         = can(api.VERBS) ? api.VERBS : ["*"]
    vpce          = module.endpoints.endpoints["execute-api"].id,
    }
  }
  statement {
    sid    = "${var.app_name}-${var.app_environment}-allow"
    effect = "Allow"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = [
      "execute-api:Invoke"
    ]
    resources = [for verb in each.value.verbs :
      "execute-api:/${each.value.api_stage}/${verb}/${each.value.resource_path}"
    ]
  }
  statement {
    sid    = "${var.app_name}-${var.app_environment}-deny"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = [
      "execute-api:Invoke"
    ]
    resources = [for verb in each.value.verbs :
      "execute-api:/${each.value.api_stage}/${verb}/${each.value.resource_path}"
    ]
    condition {
      test     = "StringNotEquals"
      variable = "aws:SourceVpce"
      values = [
        each.value.vpce
      ]
    }
  }
}
