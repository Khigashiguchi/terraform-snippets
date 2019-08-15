provider "aws" {
  region = "ap-northeast-1"
  profile = "study-terraform"
}

module "describe_regions_for_ec2" {
  source = "./iam_role"
  name = "describe-regions-for-ec2"
  identifier = "ec2.amazonaws.com"
  policy = data.aws_iam_policy_document.allow_describe_regions.json
}

data "aws_iam_policy_document" "allow_describe_regions" {
  statement {
    effect = "Allow"
    actions = ["ec2:DescribeRegions"]
    # リージョン一覧を取得する
    resources = ["*"]
  }
}

resource "aws_s3_bucket" "private" {
  # bucket名は全世界で一意
  bucket = "private-pragmatic-terraform-on-aws-hgsgtk001"

  # 復元できるように
  versioning {
    enabled = true
  }

  # 暗号化
  # 保存時に自動で暗号化・参照時に自動で複合化
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        # See also https://csrc.nist.gov/csrc/media/publications/fips/197/final/documents/fips-197.pdf
        sse_algorithm = "AES256"
      }
    }
  }
}

resource "aws_s3_bucket_public_access_block" "private" {
  bucket = aws_s3_bucket.private.id
  block_public_acls = true
  block_public_policy =  true
  ignore_public_acls = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "public" {
  bucket = "public-pragmatic-terraform-on-aws-hgsgtk001"
  acl = "public-read"

  # CORS: Cross-Origin Resource Sharing
  cors_rule {
    allowed_origins = ["https://example.com"]
    allowed_methods = ["GET"]
    allowed_headers = ["*"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket" "alb_log" {
  bucket = "alb-log-pragmatic-terraform-on-aws-hgsgtk001"

  lifecycle_rule {
    enabled = true

    expiration {
      days = "180"
    }
  }
}

resource "aws_s3_bucket_policy" "alb_log" {
  bucket = aws_s3_bucket.alb_log.id
  policy = data.aws_iam_policy_document.alb_log.json
}

data "aws_iam_policy_document" "alb_log" {
  statement {
    effect = "Allow"
    actions = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${aws_s3_bucket.alb_log.id}/*"]

    principals {
      type = "AWS"
      identifiers = ["582318560864"]
    }
  }
}
