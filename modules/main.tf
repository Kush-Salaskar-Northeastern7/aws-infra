module "networking" {
  source = "./networking"
  region = var.region
  profile = var.  profile
  availability_zones = var.availability_zones
  vpc_cidr = var.vpc_cidr
  public_subnet_cidr = var.public_subnet_cidr
  private_subnet_cidr = var.private_subnet_cidr
}