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

resource "aws_instance" "example1" {
  ami = "ami-0f9ae750e8274075b"
  instance_type = "t3.nano"

  network_interface {
    network_interface_id = "eni-0a8242d191c1126ee"
    device_index = 0
  }

  tags = {
    Name = "chapter3-1"
  }

  user_data = <<EOF
        #!/bin/bash
        yum install -y httpd
        systemctl start httpd.service
EOF
}
