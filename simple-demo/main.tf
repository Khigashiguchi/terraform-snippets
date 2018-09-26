provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region = "${var.aws_region}"
}

resource "aws_instance" "example" {
  ami = "ami-08847abae18baa040" // Amazon Linux 2 AMI (HVM), SSD Volume Type
  instance_type = "t2.micro"

  tags{
    Name = "第130回PHP勉強会"
  }
}

resource "aws_eip" "ip" {
  instance = "${aws_instance.example.id}"
}

output "ip" {
  value = "${aws_eip.ip.public_ip}"
}
