provider "aws" {
  region = "ap-northeast-1"
  profile = "study-terraform"
}

data "aws_iam_policy_document" "allow_describe_regions" {
  statement {
    effect = "Allow"
    actions = [
      "ec2.DescribeRegions"]
    # リージョン一覧を取得する
    resources = ["*"]
    # Error
    # MalformedPolicyDocument: Actions/Conditions must be prefaced by a vendor, e.g., iam, sdb, ec2, etc
    # MalformedPolicyDocument: Syntax errors in policy.
    condition {
      test = ""
      values = []
      variable = ""
    }
  }
}

resource "aws_iam_policy" "example" {
  name = "example"
  policy = data.aws_iam_policy_document.allow_describe_regions.json
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      identifiers = ["ec2.amazonaws.com"]
      type = "Service"
    }
  }
}

resource "aws_iam_role" "example" {
  name = "example"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "example" {
  role = aws_iam_role.example.name
  policy_arn = aws_iam_policy.example.arn
}
