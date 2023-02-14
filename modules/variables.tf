variable "region" {
  type = string
}

variable "profile" {
  type = string
}

variable "vpc_cidr" {
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
