provider "aws" {
  region  = "ap-northeast-1"
  profile = "study-terraform"
}

data "aws_iam_policy_document" "allow_describe_regions" {
  statement {
    effect  = "Allow"
    actions = ["ec2:DescribeRegions"]
    # リージョン一覧を取得する
    resources = ["*"]
  }
}

module "describe_regions_for_ec2" {
  source     = "./iam_role"
  name       = "describe-regions-for-ec2"
  identifier = "ec2.amazonaws.com"
  policy     = data.aws_iam_policy_document.allow_describe_regions.json
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
  bucket                  = aws_s3_bucket.private.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "public" {
  bucket = "public-pragmatic-terraform-on-aws-hgsgtk001"
  acl    = "public-read"

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
  # 一度bucket内にファイルを作成するとdestroyできないので指定
  force_destroy = true

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
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${aws_s3_bucket.alb_log.id}/*"]

    principals {
      type        = "AWS"
      identifiers = ["582318560864"]
    }
  }
}

resource "aws_vpc" "example" {
  # CIDRブロック
  # xx.xx.xx.xx/xxで定義　
  cidr_block = "10.0.0.0/16"
  # 名前解決
  # AWSのDNSサーバでの名前解決を有効にする
  enable_dns_support = true
  # publicDNSホスト名を自動割当する
  enable_dns_hostnames = true

  tags = {
    Name = "example"
  }
}

resource "aws_subnet" "public_0" {
  vpc_id = aws_vpc.example.id
  # /24単位できる
  cidr_block = "10.0.1.0/24"
  # サブネットで起動したインスタンスに自動でIPを付与
  map_public_ip_on_launch = true
  availability_zone       = "ap-northeast-1a"
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-northeast-1c"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "example" {
  vpc_id = aws_vpc.example.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.example.id
}

# ルートテーブルの1レコードに該当
# VPC以外への通信をインターネットゲートウェイ経由でインターネットへ流す
resource "aws_route" "public" {
  route_table_id         = aws_route_table.public.id
  gateway_id             = aws_internet_gateway.example.id
  destination_cidr_block = "0.0.0.0/0"
}

# どのルートテーブルを使ってルーティングするかをサブネット単位で判断
# ルートテーブルとサブネットを関連付け
resource "aws_route_table_association" "public_0" {
  subnet_id      = aws_subnet.public_0.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

# private networkの作成
resource "aws_subnet" "private_0" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.65.0/24"
  availability_zone       = "ap-northeast-1a"
  map_public_ip_on_launch = false
}

resource "aws_subnet" "private_1" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.66.0/24"
  availability_zone       = "ap-northeast-1c"
  map_public_ip_on_launch = false
}

resource "aws_route_table" "private_0" {
  vpc_id = aws_vpc.example.id
}

resource "aws_route_table" "private_1" {
  vpc_id = aws_vpc.example.id
}

# defaultでNAT Gatewayにrouting
resource "aws_route" "private_0" {
  route_table_id         = aws_route_table.private_0.id
  nat_gateway_id         = aws_nat_gateway.nat_gateway_0.id
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_route" "private_1" {
  route_table_id         = aws_route_table.private_1.id
  nat_gateway_id         = aws_nat_gateway.nat_gateway_1.id
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_route_table_association" "private_0" {
  subnet_id      = aws_subnet.private_0.id
  route_table_id = aws_route_table.private_0.id
}

resource "aws_route_table_association" "private_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private_1.id
}

# NAT Network Address Translation
resource "aws_eip" "nat_gateway_0" {
  # EIP in VPC
  # See also https://www.terraform.io/docs/providers/aws/r/eip.html#vpc
  vpc = true
  # EIP may require IGW to exist prior to association. Use depends_on to set an explicit dependency on the IGW.
  # See also https://www.terraform.io/docs/providers/aws/r/eip.html
  depends_on = [aws_internet_gateway.example]
}

resource "aws_eip" "nat_gateway_1" {
  vpc        = true
  depends_on = [aws_internet_gateway.example]
}

# NAT gatewayをpublic subnetに配置
resource "aws_nat_gateway" "nat_gateway_0" {
  allocation_id = aws_eip.nat_gateway_0.id
  subnet_id     = aws_subnet.public_0.id
  # 依存先作成後にこのリソースが作成されることを保証する
  depends_on = [aws_internet_gateway.example]
}

resource "aws_nat_gateway" "nat_gateway_1" {
  allocation_id = aws_eip.nat_gateway_1.id
  subnet_id     = aws_subnet.public_1.id
  depends_on    = [aws_internet_gateway.example]
}

# Firewall
# AWSではsubnetレベルの Network ACL・インスタンスレベルの Security Groupがある
module "example_sg" {
  source      = "./security_group"
  name        = "module-sg"
  vpc_id      = aws_vpc.example.id
  port        = 80
  cidr_blocks = ["0.0.0.0/0"]
}

# ALB Application Load Balancer
# Route 53・ACM AWS Certificate Managerを使いHTTPSでアクセス
# ALB クロスゾーン負荷分散に標準対応
resource "aws_lb" "example" {
  name = "example"
  # type in ("application", "network")
  # See also https://www.terraform.io/docs/providers/aws/r/lb.html#load_balancer_type
  load_balancer_type = "application"
  # true = internal, false = internet-facing
  internal = false
  # timeout = default 60
  idle_timeout = 60
  # 削除保護
  # productionではtrueにしておきたいがdestroyしたいのでfalseへ
  enable_deletion_protection = false

  subnets = [
    aws_subnet.public_0.id,
    aws_subnet.public_1.id,
  ]

  access_logs {
    bucket  = aws_s3_bucket.alb_log.id
    enabled = true
  }

  security_groups = [
    module.http_sg.security_group_id,
    module.https_sg.security_group_id,
    module.http_redirect_sg.security_group_id,
  ]
}

output "alb_dns_name" {
  value = aws_lb.example.dns_name
}

module "http_sg" {
  source      = "./security_group"
  name        = "http-sg"
  vpc_id      = aws_vpc.example.id
  port        = 80
  cidr_blocks = ["0.0.0.0/0"]
}

module "https_sg" {
  source      = "./security_group"
  name        = "https-sg"
  vpc_id      = aws_vpc.example.id
  port        = 443
  cidr_blocks = ["0.0.0.0/0"]
}

module "http_redirect_sg" {
  source      = "./security_group"
  name        = "http-redirect-sg"
  vpc_id      = aws_vpc.example.id
  port        = 8080
  cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port              = "80"
  # ALBはHTTP/HTTPSのみ
  protocol = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "これは『HTTP』です"
      status_code  = "200"
    }
  }
}
