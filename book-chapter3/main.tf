provider "aws" {
  region  = "ap-northeast-1"
  profile = "study-terraform"
}

variable "example_instance_type" {
  default = "t3.micro"
}

resource "aws_instance" "example" {
  ami           = "ami-0f9ae750e8274075b"
  instance_type = var.example_instance_type

  tags = {
    Name = "chapter3"
  }

  user_data = <<EOF
        #!/bin/bash
        yum install -y httpd
        systemctl start httpd.service
EOF
}
