variable "region" {
  type = string
}

variable "profile" {
  type = string
}

variable "domain_profile" {
  type = string
}

variable "domain" {
  type = string
  default = "kushsalaskar.me"
}

variable "vpc_cidr" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_password" {
  type = string
}

variable "availability_zones" {
  type = list(any)
}

variable "public_subnet_cidr" {
  type = list(any)
}

variable "private_subnet_cidr" {
  type = list(any)
}

variable "ami_id" {
  type = string
}
