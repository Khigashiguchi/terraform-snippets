/*====
RDS
=====*/

/* subnet used by rds */
resource "aws_db_subnet_group" "rds_subnet_group" {
  name         = "${var.environment}-rds-subnet-group"
  description  = "RDS subnet group"
  subnet_ids   = ["${var.subnet_ids}"]

  tags {
    Environemt = "${var.environment}"
  }
}

/* Security Group for resource that want to access the Database */
resource "aws_security_group" "db_access_sg" {
  vpc_id       = "${var.vpc_id}"
  name         = "${var.environment}-db-access-sg"
  description  = "Allow access to RDS"

  tags {
    Name        = "${var.environment}-db-access-sg"
    Environemt  = "${var.environment}"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "${var.environment}-rds-sg"
  description = "${var.environment} Security Group"
  vpc_id      = "${var.vpc_id}"

  tags {
    Name        = "${var.environment}-rds-sg"
    Environemt  = "${var.environment}"
  }

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = ["${aws_security_group.db_access_sg.id}"]
  }

  engress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "rds" {
  identifier             = "${var.environment}-database"
  allocated_storage      = "${var.allocated_storage}"
  engine                 = "postgres"
  engine_version         = "9.6.6"
  instance_class         = "${var.instance_class}"
  mulit_az               = "${var.mulit_az}"
  name                   = "${var.database_name}"
  username               = "${var.database_username}"
  password               = "${var.database_password}"
  db_subnet_group_name   = "${aws_db_subnet_group.rds_subnet_group.id}"
  vpc_security_group_ids = ["${aws_security_group.rds_sg.id}"]
  skip_final_snapshot    = true
  snapshot_identifier    = "rds-${var.environment}-snapshot"

  tags {
    Enviromment = "${var.environment}"
  }
}
