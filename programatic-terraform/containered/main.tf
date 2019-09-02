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

# Route 53
# Host zone data source definition
data "aws_route53_zone" "example" {
  name = "hgsgtk.ninja"
}

# Create Host zone
resource "aws_route53_zone" "test_example" {
  name = "test.hgsgtk.ninja"
}

resource "aws_route53_record" "example" {
  zone_id = data.aws_route53_zone.example.zone_id
  name    = data.aws_route53_zone.example.name
  # DNSレコードタイプ A / CNAME
  # AWS独自拡張のALIASレコードの場合はAを指定
  type = "A"

  # ALIASレコード
  # DNSからみるとただのAレコード、AWSサービスと統合されているため、S3やCloudFrontも指定可能
  alias {
    name    = aws_lb.example.dns_name
    zone_id = aws_lb.example.zone_id
    # Route53によるALBへのHealth Check
    # See also https://aws.amazon.com/jp/premiumsupport/knowledge-center/load-balancer-marked-unhealthy/
    evaluate_target_health = true
  }
}


# ACM AWS Certificate Manager
resource "aws_acm_certificate" "example" {
  # set domain name
  # * も可能
  domain_name = data.aws_route53_zone.example.name
  # ドメイン名の追加 ex. test.example.com
  subject_alternative_names = []
  # 検証方法
  # Email or DNS
  # 自動更新可能 DNS検証
  validation_method = "DNS"

  # 新しいSSL証明書再作成のサービス影響の制御
  lifecycle {
    # 新しいリソースを作ってから削除する
    create_before_destroy = true
  }
}

# SSL証明書の検証
# See also https://www.terraform.io/docs/providers/aws/r/route53_record.html
resource "aws_route53_record" "example_certificate" {
  name = aws_acm_certificate.example.domain_validation_options[0].resource_record_name
  type = aws_acm_certificate.example.domain_validation_options[0].resource_record_type
  records = [
    aws_acm_certificate.example.domain_validation_options[0].resource_record_value
  ]
  zone_id = data.aws_route53_zone.example.id
  ttl     = 60
}

resource "aws_acm_certificate_validation" "example" {
  certificate_arn = aws_acm_certificate.example.id
  validation_record_fqdns = [
    aws_route53_record.example_certificate.fqdn
  ]
}

# HTTPS の ALB listemner作成
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.example.arn
  port              = "443"
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate.example.arn
  ssl_policy        = "ELBSecurityPolicy-2016-08"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "これは『HTTPS』です"
      status_code  = "200"
    }
  }
}

# HTTPのリダイレクト
resource "aws_lb_listener" "redirect_http_to_https" {
  load_balancer_arn = aws_lb.example.arn
  port              = "8080"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# リクエストフォワーディング
# 任意のターゲットにリクエストをフォワード
# Target Group ALBがリクエストをフォワードする先
resource "aws_lb_target_group" "example" {
  name = "example"
  # EC2 instance, IP address, lambda関数などを指定
  # FargateではIPアドレスでのルーティングが必須
  target_type = "ip"
  # IP指定した際に設定する
  vpc_id   = aws_vpc.example.id
  port     = 80
  protocol = "HTTP"
  # 登録解除待機時間
  # ターゲット登録解除前にALBが待機する時間
  # 秒単位指定
  deregistration_delay = 300

  health_check {
    path                = "/" # ヘルスチェックで使用するパス
    healthy_threshold   = 5   # 正常判定を行うまでの実行回数
    unhealthy_threshold = 2   # 異常判定を行うまでの実行回数
    timeout             = 5
    interval            = 30
    matcher             = 200            # HTTPステータスコード
    port                = "traffic-port" # 使用ポート、ここでは上で定義した80になる
    protocol            = "HTTP"
  }

  # ALBを作ってからターゲットグループが作られるように
  depends_on = [aws_lb.example]
}

# リスナールール
resource "aws_lb_listener_rule" "example" {
  listener_arn = aws_lb_listener.https.arn
  # 複数定義可能、数字が低いほど有先順位が高い
  priority = 100

  # フォワード先のターゲットグループ
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.example.arn
  }

  # 条件指定 ex. /img/*, example.com
  condition {
    field = "path-pattern"
    # /* はすべてのパスがマッチする
    values = ["/*"]
  }
}

# ECS
# Cluster
resource "aws_ecs_cluster" "example" {
  name = "example"
}

# Task Definition
# Task = コンテナ実行単位
resource "aws_ecs_task_definition" "example" {
  # タスク定義名のPrefix
  # これにリビジョン番号を付与したものがタスク定義名
  # ex. example:1
  family = "example"
  # タスクサイズ
  # CPU Unitの整数表現(ex. 512, 1024)かvCPU(ex. 1 vCPU)も文字列表現で設定
  cpu = "256"
  # MiBの整数表現(ex. 1024)かGBの文字列表現(ex. 1 GB)
  memory = "512"
  # Fargate起動タイプではこちら
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  container_definitions    = file("./container_definitioins.json")
  execution_role_arn       = module.ecs_task_execution_role.iam_role_arn
}

# ECSサービス
resource "aws_ecs_service" "example" {
  name            = "example"
  cluster         = aws_ecs_cluster.example.arn
  task_definition = aws_ecs_task_definition.example.arn
  desired_count   = 2
  launch_type     = "FARGATE"
  # 明示的に指定しような
  platform_version = "1.3.0"
  # ヘルスチェック猶予期間
  health_check_grace_period_seconds = 60

  network_configuration {
    assign_public_ip = false
    security_groups  = [module.nginx_sg.security_group_id]

    subnets = [
      aws_subnet.private_0.id,
      aws_subnet.private_1.id,
    ]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.example.arn
    container_name   = "example"
    container_port   = 80

  }

  lifecycle {
    ignore_changes = [task_definition]
  }
}

module "nginx_sg" {
  source      = "./security_group"
  name        = "nginx-sg"
  vpc_id      = aws_vpc.example.id
  port        = 80
  cidr_blocks = [aws_vpc.example.cidr_block]
}

# Logging
resource "aws_cloudwatch_log_group" "for_ecs" {
  name = "/ecs/example"
  # ログの保持期間
  retention_in_days = 180
}

data "aws_iam_policy" "ecs_task_execution_role_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "ecs_task_execution" {
  # 既存のポリシーを継承する
  source_json = data.aws_iam_policy.ecs_task_execution_role_policy.policy

  statement {
    effect    = "Allow"
    actions   = ["ssm:GetParameters", "kms:Decrypt"]
    resources = ["*"]
  }
}

module "ecs_task_execution_role" {
  source     = "./iam_role"
  name       = "ecs-task-execution"
  identifier = "ecs-tasks.amazonaws.com"
  policy     = data.aws_iam_policy_document.ecs_task_execution.json
}

# バッチ設計
# バッチ処理は、オンライン処理とは異なる関心事を示す
# アプリケーションレベルでどこまで制御し、ジョブ管理システムでどこまでサポートするか
# 重要な観点は以下の4つ
# - ジョブ管理
# - エラーハンドリング
#   - エラー通知が重要、失敗した場合検知してリカバリが必要
#   - ロギングも必須、スタックトレースなどの情報は確実にログ出力
# - リトライ
#   - 自動で指定回数リトライできる必要、少なくとも手動リトライ
# - 依存関係制御
#   - ジョブが増える場合依存関係制御が必要
#   - ジョブA->B->C
#   - 時間をずらして暗黙的な依存関係制御を行うのはアンチパターン

# ジョブ管理
# - 手軽なものはcron、手軽な反面管理が難しい
# - ジョブ管理システム
#   - Rundeck, JP1
# - AWSには現在ジョブ管理システムは存在しない

# ECS Scheduled Task
# ECSのタスクを定期実行
# 単体では、エラーハンドリング・リトライなどは無く、アプリケーションでやる必要

resource "aws_cloudwatch_log_group" "for_ecs_scheduled_tasks" {
  name              = "/ecs-scheduled-tasks/example"
  retention_in_days = 180
}

resource "aws_ecs_task_definition" "example_batch" {
  family                   = "example-batch"
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  container_definitions    = file("./batch_container_definitions.json")
  execution_role_arn       = module.ecs_task_execution_role.iam_role_arn
}

module "ecs_events_role" {
  source     = "./iam_role"
  name       = "ecs-events"
  identifier = "events.amazonaws.com"
  policy     = data.aws_iam_policy.ecs_events_role_policy.policy
}

# CloudWatchイベントIAM
# AmazonEC2ContainerServiceEventsRoleポリシー
data "aws_iam_policy" "ecs_events_role_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceEventsRole"
}

# CloudWatchイベントルール
resource "aws_cloudwatch_event_rule" "example_batch" {
  name        = "example_batch"
  description = "very important batch procedure"
  # cron or rate
  schedule_expression = "cron(*/2 * * * ? *)"
}

# CloudWatchイベントターゲット
resource "aws_cloudwatch_event_target" "example_batch" {
  target_id = "example-batch"
  rule      = aws_cloudwatch_event_rule.example_batch.name
  role_arn  = module.ecs_events_role.iam_role_arn
  arn       = aws_ecs_cluster.example.arn

  ecs_target {
    launch_type         = "FARGATE"
    task_count          = 1
    platform_version    = "1.3.0"
    task_definition_arn = aws_ecs_task_definition.example_batch.arn

    network_configuration {
      assign_public_ip = "false"
      subnets          = [aws_subnet.private_0.id]
    }
  }
}
