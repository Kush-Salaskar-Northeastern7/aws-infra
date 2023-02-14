resource "aws_vpc" "vpc" {
  cidr_block = var.vpc_cidr
}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.vpc.id
}

resource "aws_subnet" "public_subnet" {
  count = length(var.availability_zones)
  vpc_id = aws_vpc.vpc.id
  cidr_block = var.public_subnet_cidr[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "public-subnet-${count.index}"
  }
}

resource "aws_route_table_association" "public_route_table_association" {
  count = length(var.availability_zones)
  subnet_id = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_subnet" "private_subnet" {
  count = length(var.availability_zones)
  vpc_id = aws_vpc.vpc.id
  cidr_block = var.private_subnet_cidr[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "private-subnet-${count.index}"
  }
}

resource "aws_route_table_association" "private_route_table_association" {
  count = length(var.availability_zones)
  subnet_id = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}
