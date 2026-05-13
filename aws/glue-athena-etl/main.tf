################################################################################
# AWS Glue + Athena ETL pattern
#
# Matches the cloud-data-migration project described in my CV:
# raw zone in S3, AWS Glue crawler infers schema, Athena queries it with
# the Glue Data Catalog, partitions stored in S3 by date.
#
# Layout the module assumes:
#   s3://${bucket}/raw/<source>/year=YYYY/month=MM/day=DD/...
#   s3://${bucket}/curated/<table>/...
#
# This is the IaC piece. The actual ETL job lives in glue-job.py (separate
# repo / S3 upload) — keeping job code in Terraform is an anti-pattern.
################################################################################

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

variable "name"   { type = string }
variable "region" { type = string }

################################################################################
# Data lake bucket (server-side encrypted, versioned, no public access)
################################################################################

resource "aws_s3_bucket" "lake" {
  bucket = "${var.name}-lake-${data.aws_caller_identity.me.account_id}"
}

data "aws_caller_identity" "me" {}

resource "aws_s3_bucket_versioning" "lake" {
  bucket = aws_s3_bucket.lake.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lake" {
  bucket = aws_s3_bucket.lake.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.lake.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "lake" {
  bucket                  = aws_s3_bucket.lake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "lake" {
  bucket = aws_s3_bucket.lake.id

  rule {
    id     = "raw-zone-glacier-after-90d"
    status = "Enabled"
    filter { prefix = "raw/" }
    transition {
      days          = 90
      storage_class = "GLACIER_IR"
    }
  }

  rule {
    id     = "curated-keep"
    status = "Enabled"
    filter { prefix = "curated/" }
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
}

resource "aws_kms_key" "lake" {
  description             = "${var.name} data lake encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

################################################################################
# Glue catalog: database + crawler
################################################################################

resource "aws_glue_catalog_database" "this" {
  name = replace("${var.name}_lake", "-", "_")
}

resource "aws_iam_role" "glue" {
  name = "${var.name}-glue"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_s3" {
  role = aws_iam_role.glue.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:GetObject", "s3:ListBucket", "s3:PutObject", "s3:DeleteObject"]
      Resource = [
        aws_s3_bucket.lake.arn,
        "${aws_s3_bucket.lake.arn}/*",
      ]
    }, {
      Effect = "Allow"
      Action = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:ReEncrypt*", "kms:DescribeKey"]
      Resource = [aws_kms_key.lake.arn]
    }]
  })
}

resource "aws_glue_crawler" "raw" {
  database_name = aws_glue_catalog_database.this.name
  name          = "${var.name}-raw"
  role          = aws_iam_role.glue.arn
  schedule      = "cron(0 */6 * * ? *)"   # every 6 hours

  s3_target {
    path = "s3://${aws_s3_bucket.lake.bucket}/raw/"
  }

  recrawl_policy {
    recrawl_behavior = "CRAWL_NEW_FOLDERS_ONLY"
  }

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }
}

################################################################################
# Glue ETL job (script path; the script itself lives in S3, uploaded separately)
################################################################################

resource "aws_glue_job" "etl" {
  name              = "${var.name}-etl"
  role_arn          = aws_iam_role.glue.arn
  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 5
  timeout           = 60   # minutes

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.lake.bucket}/scripts/etl.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--enable-metrics"                   = "true"
    "--enable-spark-ui"                  = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--TempDir"                          = "s3://${aws_s3_bucket.lake.bucket}/tmp/"
    "--database_name"                    = aws_glue_catalog_database.this.name
    "--target_path"                      = "s3://${aws_s3_bucket.lake.bucket}/curated/"
  }

  execution_property {
    max_concurrent_runs = 1
  }
}

################################################################################
# Athena workgroup (query results encrypted, billing-capped)
################################################################################

resource "aws_athena_workgroup" "this" {
  name = var.name

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    bytes_scanned_cutoff_per_query     = 10 * 1024 * 1024 * 1024  # 10 GiB

    result_configuration {
      output_location = "s3://${aws_s3_bucket.lake.bucket}/athena-results/"
      encryption_configuration {
        encryption_option = "SSE_KMS"
        kms_key_arn       = aws_kms_key.lake.arn
      }
    }
  }
}

output "athena_workgroup" {
  value = aws_athena_workgroup.this.name
}

output "lake_bucket" {
  value = aws_s3_bucket.lake.bucket
}

output "glue_database" {
  value = aws_glue_catalog_database.this.name
}
