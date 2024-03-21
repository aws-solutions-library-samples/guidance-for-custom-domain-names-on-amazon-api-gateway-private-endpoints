resource "aws_kms_key" "route53_logs_cmk" {
  description             = "KMS key for encrypting Route 53 logs in CloudWatch Logs"
  enable_key_rotation = true
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Id": "key-default-1",
  "Statement": [
    {
      "Sid": "Enable IAM User Permissions",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:${data.aws_partition.current.id}:iam::${data.aws_caller_identity.current.account_id}:root" 
      },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "Allow use of the key",
      "Effect": "Allow",
      "Principal": {
        "Service": "logs.${data.aws_region.current.name}.amazonaws.com"
      }, 
      "Action": "kms:Encrypt",
      "Resource": "*"
    }
  ]
}
POLICY
}
