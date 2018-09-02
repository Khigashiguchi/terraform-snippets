/*====
ECR repository to store our Docker images
=====*/
resource "aws_ecr_repository" "openjobs_app" {
  name = "${var.repository_name}"
}

/*====
ECS cluster
======*/
resource "aws_ecs_cluster" "cluster" {
  name = "${var.environment}-ecs-cluster"
}

/*====
ECS task definitions
=====*/
/* the task definition for the web service */
data "template_file" "web_task" {
  template = "${file("${path.module}/tasks/web_task_definition.json")}"

  vars {
    image           = "${aws_ecr_repository.openjobs_app.repository_url}"
    secret_key_base = "${var.secret_key_base}"
    database_url    = "postgresql://${var.database_username}:${var.database_password}@${var.databse_endpoint}:5432/${var.database_name}?encoding=utf8&pool=40"
    log_group       = "${aws_cloudwatch_log_group.openjobs.name}"
  }
}

resource "aws_ecs_task_definition" "web" {
  family                   = "${var.environment}_web"
  container_definitions    = "${data.template_file.web_task.rendered}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = "${aws_iam_role.ecs_execution_role.arn}"
  task_role_arn            = "${aws_iam_role.ecs_execution_role.arn}"
}

/* the task definition for the db migration */
data "template_file" "db_migrate_task" {
  template = "${file("${path.module}/tasks/db_migrate_task_definition.json")}"

  vars {
    image             = "${aws_ecr_repository.openjobs_app.repository_url}"
    secret_key_base   = "${var.secret_key_base}"
    database_url      = "postgresql://${var.database_username}:${var.database_password}@${var.databse_endpoint}:5432/${var.database_name}?encoding=utf8&pool=40"
    log_group         = "openjobs"
  }
}

resource "aws_ecs_task_definition" "db_migrate" {
  family                   = "${var.environment}_db_migrate"
  container_definitions    = "${data.template_file.db_migrate_task.rendered}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = "${aws_iam_role.ecs_execution_role.arn}"
  task_role_arn            = "${aws_iam_role.ecs_execution_role.arn}"
}

resource "aws_alb_target_group" "alb_target_group" {
  name        = "${var.environment}-alb-target-group-${random_id.target_group_suffix.hex}"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = "${var.vpc_id}"
  target_type = "ip"

  lifecycle {
    create_before_destroy = true
  }
}

/* security group for ALB */
resource "aws_security_group" "web_inbound_sg" {
  name        = "${var.environment}-web-inbound-sg"
  description = "Allow HTTP from Anywhere into ALB"
  vpc_id      = "${var.vpc_id}"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_block  = ["0.0.0.0/0"]
  }

  tags {
    Name = "${var.environment}-web-inbound-sg"
  }
}

resource "aws_alb" "alb_openjobs" {
  name            = "${var.environment}-alb-openjobs"
  subnets         = ["${var.public_subnets_ids}"]
  security_groups = ["${var.security_group_ids}", "${aws_security_group.web_inbound_sg.id}"]

  tags {
    Name        = "${var.environment}-alb-openjobs"
    Environment = "${var.environment}"
  }
}

resource "aws_alb_listener" "openjobs" {
  load_balancer_arn = "${aws_alb.alb_openjobs.arn}"
  port = "80"
  protocol = "HTTP"
  depends_on = ["aws_alb_target_group.alb_target_group"]

  default_action {
    target_group_arn  = "${aws_alb_target_group.alb_target_group.arn}"
    type              = "forward"
  }
}

/*====
ECS service
=====*/
/* Security Group for ECS */
resource "aws_security_group" "ecs_service" {
  vpc_id      = "${var.vpc_id}"
  name        = "${var.environment}-ecs-service-sg"
  description = "Allow egress from container"

  egress {
    form_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name       = "${var.environment}-ecs-service-sg"
    Environemt = "${var.environment}"
  }
}

/* Simply specify the family to find the lastest ACTIVE revision in that family */
data "aws_ecs_task_definition" "web" {
  task_definition = "${aws_ecs_task_definition.web.family}"
}

resource "aws_ecs_service" "web" {
  name            = "${var.environment}-web"
  task_definition = "${aws_ecs_task_definition.web.family}:${max("${aws_ecs_task_definition.web.revision}", "${data.aws_ecs_task_definition.web.revision}")}"
  desired_count   = 2
  launch_type     = "FARGATE"
  cluster         = "${aws_ecs_cluster.cluster.id}"
  depends_on      = ["aws_iam_role_policy.ecs_service_role_policy"]

  network_configuration {
    security_groups = ["${var.security_groups_ids}", "${aws_security_group.ecs_service.id}"]
    subnets         = ["${var.subnets_ids}"]
  }

  load_balancer {
    target_group_arn = "${aws_alb_target_group.alb_target_group.arn}"
    container_name   = "web"
    container_port   = "80"
  }

  depends_on = ["aws_alb_target_group.alb_target_group"]
}

resource "aws_appautoscaling_target" "target" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.web.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  role_arn           = "${aws_iam_role.ecs_autoscale_role.arn}"
  min_capacity       = 1
  max_capacity       = 4
}

resource "aws_appautoscaling_policy" "up" {
  name               = "${var.environment}_scale_up"
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.web.name}"
  scalable_dimension = "ecs:service:DesiredCount"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 1
    }
  }

  depends_on = ["aws_appautoscaling_target.target"]
}

resource "aws_appautoscaling_policy" "down" {
  name               = "${var.environment}_scale_down"
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.web.name}"
  scalable_dimension = "ecs:service:DesiredCount"

  step_scaling_policy_configuration {
    adjustment_type = "ChangeInCapacity"
    cooldown        = 60
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment = -1
    }
  }

  depends_on ["aws_appautoscaling_target.target"]
}

/* metric used for auto scale */
resource "aws_cloudwatch_metric_alarm" "service_cpu_high" {
  alarm_name          = "${var.environment}_openjobs_web_cpu_utilization_high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_preriods = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "85"

  dimensions {
    ClusterName = "${aws_ecs_cluster.cluster.name}"
    ServiceName = "${aws_ecs_service.web.name}"
  }

  alarm_actions = ["${aws_appautoscaling_policy.up.arn}"]
  ok_actions    = ["${aws_appautoscaling_policy.down.arn}"]
}
