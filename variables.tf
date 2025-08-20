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
