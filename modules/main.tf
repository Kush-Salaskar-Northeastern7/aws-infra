module "networking" {
  source              = "./networking"
  region              = var.region
  profile             = var.profile
  domain              = var.domain
  domain_profile      = var.domain_profile
  availability_zones  = var.availability_zones
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidr  = var.public_subnet_cidr
  private_subnet_cidr = var.private_subnet_cidr
  ami_id              = var.ami_id
  db_name             = var.db_name
  db_password         = var.db_password
  key_name            = var.key_name
}