data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # One bucket per data lake layer. The account id makes the names globally unique
  # (S3 names are shared by every AWS account) without inventing a random suffix.
  lake_layers  = toset(["raw", "standard", "curated"])
  bucket_names = { for layer in local.lake_layers : layer => "banvic-${layer}-${local.account_id}" }

  aws_credentials_secret_name = "aws-lake-credentials"
}

# --- Data lake buckets ------------------------------------------------------
resource "aws_s3_bucket" "lake" {
  for_each = local.lake_layers

  bucket = local.bucket_names[each.key]

  # Lets `terraform destroy` empty the bucket (including old versions) first.
  # Acceptable here: the data is a re-creatable copy of the CSV files.
  force_destroy = true
}

# Keeps previous versions of overwritten objects: a safety net for the
# "overwrite the same path on every run" strategy (D5).
resource "aws_s3_bucket_versioning" "lake" {
  for_each = aws_s3_bucket.lake

  bucket = each.value.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lake" {
  for_each = aws_s3_bucket.lake

  bucket = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "lake" {
  for_each = aws_s3_bucket.lake

  bucket = each.value.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- Pipeline identity (least privilege) ------------------------------------
# The identity Airflow/Meltano use to talk to S3. It can only read and write
# objects in the three lake buckets: no admin rights, no other AWS service.
# (The Glue stage will need its own role later; this user stays S3-only.)
resource "aws_iam_user" "pipeline" {
  name = "banvic-pipeline"
}

data "aws_iam_policy_document" "pipeline" {
  statement {
    sid       = "ListLakeBuckets"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [for b in aws_s3_bucket.lake : b.arn]
  }

  statement {
    sid       = "ReadWriteLakeObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [for b in aws_s3_bucket.lake : "${b.arn}/*"]
  }
}

resource "aws_iam_user_policy" "pipeline" {
  name   = "lake-read-write"
  user   = aws_iam_user.pipeline.name
  policy = data.aws_iam_policy_document.pipeline.json
}

resource "aws_iam_access_key" "pipeline" {
  user = aws_iam_user.pipeline.name
}

# The key goes straight from Terraform into a Kubernetes Secret: nobody sees it
# or pastes it anywhere. The variable names are the ones the AWS SDKs (boto3,
# used by Meltano's S3 target) read automatically.
resource "kubernetes_secret_v1" "aws_credentials" {
  metadata {
    name      = local.aws_credentials_secret_name
    namespace = kubernetes_namespace_v1.airflow.metadata[0].name
    labels    = local.common_labels
  }

  data = {
    AWS_ACCESS_KEY_ID     = aws_iam_access_key.pipeline.id
    AWS_SECRET_ACCESS_KEY = aws_iam_access_key.pipeline.secret
    AWS_DEFAULT_REGION    = var.aws_region
  }
}

# --- Cost alert -------------------------------------------------------------
# Budgets only warn, they never stop anything. Two e-mails: one when the real
# spend reaches 80% of the limit, one when the forecast says it will pass 100%.
resource "aws_budgets_budget" "monthly" {
  name         = "banvic-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_email]
  }
}

output "lake_buckets" {
  description = "Bucket name of each data lake layer."
  value       = local.bucket_names
}
