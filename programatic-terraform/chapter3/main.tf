provider "aws" {
  region  = "ap-northeast-1"
  profile = "study-terraform"
}

module "dev_server" {
  source = "http_server"
  instance_type = "t3.micro"
}

output "public_dns" {
  value = module.dev_server.public_dns
}
