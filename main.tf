terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.92"
    }
  }
  required_version = ">= 1.2"
}

provider "aws" {
  region = var.aws_region
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  owners = ["amazon"]
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.project_name}-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}

resource "aws_subnet" "dmz" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.dmz_subnet_cidr
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project_name}-dmz-subnet" }
}

resource "aws_subnet" "internal" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidr
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.project_name}-internal-subnet" }
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.project_name}-nat-eip" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.dmz.id
  tags          = { Name = "${var.project_name}-nat-gateway" }
  depends_on    = [aws_internet_gateway.igw]
}

resource "aws_route_table" "dmz" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${var.project_name}-dmz-rt" }
}

resource "aws_route_table_association" "dmz_assoc" {
  subnet_id      = aws_subnet.dmz.id
  route_table_id = aws_route_table.dmz.id
}

resource "aws_route_table" "internal" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "${var.project_name}-internal-rt" }
}

resource "aws_route_table_association" "internal_assoc" {
  subnet_id      = aws_subnet.internal.id
  route_table_id = aws_route_table.internal.id
}

resource "aws_security_group" "dmz_web_ssh" {
  name   = "${var.project_name}-dmz-web-ssh"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-dmz-web-ssh" }
}

resource "aws_security_group" "internal_ssh_from_dmz" {
  name   = "${var.project_name}-internal-ssh-from-dmz"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.dmz_web_ssh.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-internal-ssh-from-dmz" }
}

#jumpbox in DMZ
resource "aws_instance" "jumpbox" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.dmz.id
  key_name               = "ubuntu-server"                    // will be team-key, share private team-key.pem to everyone
  vpc_security_group_ids = [aws_security_group.dmz_web_ssh.id]

  tags = { Name = "${var.project_name}-jumpbox" }
}

# web server in DMZ
resource "aws_instance" "web" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.dmz.id
  key_name               = "ubuntu-server"
  vpc_security_group_ids = [aws_security_group.dmz_web_ssh.id]

  // start simple apache2 server
  user_data = <<-EOF
  #!/bin/bash
  apt-get update
  apt-get install -y apache2
  systemctl start apache2
  systemctl enable apache2
  printf "Hello from DMZ web host \n" | tee /var/www/html/index.html
  EOF

  tags = { Name = "${var.project_name}-web" }
}

# internal host
resource "aws_instance" "internal-box" {
  ami             = data.aws_ami.ubuntu.id
  instance_type   = "t2.micro"
  key_name        = "ubuntu-server"                   // suggestion here? use the same key pair as the other instances? if yes, then need to scp the key file from the host/jumpbox to the internal instance? 
  subnet_id       = aws_subnet.internal.id
  security_groups = [aws_security_group.internal_ssh_from_dmz.id]

  tags = { Name = "${var.project_name}-internal-box" }
}

#S3 static website
resource "aws_s3_bucket" "website" {
  bucket = "${var.project_name}-website-bucket"
  tags   = { Name = "${var.project_name}-website-bucket" }
}

resource "random_id" "bucket_id" { //to make the bucket name globally unique
  byte_length = 4
}

resource "aws_s3_bucket_ownership_controls" "this" { //enforce bucket-owner
  bucket = aws_s3_bucket.website.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "this" { // allow public policies
  bucket = aws_s3_bucket.website.id

  block_public_acls       = false
  ignore_public_acls      = false
  block_public_policy     = false
  restrict_public_buckets = false
}

# Static website hosting
resource "aws_s3_bucket_website_configuration" "this" {
  bucket = aws_s3_bucket.website.id
  index_document {
    suffix = "index.html"
  }
}

//public read of objects only (no ListBucket)
data "aws_iam_policy_document" "allow_read_only_access"{
  statement {
    sid = "PublicReadGetObject"
    effect = "Allow"
    principals {
      type = "AWS"
      identifiers = [ "*" ]
    }

    actions = [
      "s3:GetObject"
    ]
    resources = ["${aws_s3_bucket.website.arn}/*"]
}
}

resource "aws_s3_bucket_policy" "public_read"{
  bucket = aws_s3_bucket.website.id
  policy = data.aws_iam_policy_document.allow_read_only_access.json
  depends_on = [ aws_s3_bucket_public_access_block.this, aws_s3_bucket_ownership_controls.this ]
}

# example index page
resource "aws_s3_object" "index" {
  bucket = aws_s3_bucket.website.id
  key    = "index.html"
  content = "<h1>Hello</h1>"
  content_type = "text/html"
}

### variables

variable "aws_region" {
  type    = string
  default = "us-east-2"

}

variable "project_name" {
  type    = string
  default = "fall-redblueteam"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "dmz_subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  type    = string
  default = "10.0.2.0/24"
}

variable "create_website_bucket" {
  type    = bool
  default = false
}

variable "allowed_ssh_cidr" {
  type = string
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}


### outputs
output "vpc_id" {
  value = aws_vpc.main.id
}
output "dmz_subnet_id" {
  value = aws_subnet.dmz.id
}
output "internal_subnet_id" {
  value = aws_subnet.internal.id
}
output "jumpbox_public_ip" {
  value = aws_instance.jumpbox.public_ip
}
output "web_public_ip" {
  value = aws_instance.web.public_ip
}
output "internal_private_ip" {
  value = aws_instance.internal-box.private_ip
}
output "s3_website_endpoint" {
  description = "if bucket is created, this is the http endpoint"
  value       = aws_s3_bucket.website.website_endpoint
}