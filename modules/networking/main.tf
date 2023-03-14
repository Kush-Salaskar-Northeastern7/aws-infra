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
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = var.public_subnet_cidr[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "public-subnet-${count.index}"
  }
}

resource "aws_route_table_association" "public_route_table_association" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_subnet" "private_subnet" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = var.private_subnet_cidr[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "private-subnet-${count.index}"
  }
}

resource "aws_route_table_association" "private_route_table_association" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_security_group" "application_sg" {
  name_prefix = "my_security_group"
  vpc_id      = aws_vpc.vpc.id


  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3001
    to_port     = 3001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_instance_profile" "webapp_instance_profile" {
  name = "webapp_instance_profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_instance" "webserver" {
  ami                         = var.ami_id
  instance_type               = "t2.micro"
  vpc_security_group_ids      = [aws_security_group.application_sg.id]
  subnet_id                   = aws_subnet.public_subnet[0].id
  associate_public_ip_address = true
  root_block_device {
    volume_size           = 50
    volume_type           = "gp2"
    delete_on_termination = true
  }
  tags = {
    Name = "webserver"
  }
  iam_instance_profile = aws_iam_instance_profile.webapp_instance_profile.name
  # Disable termination protection
  disable_api_termination = true

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              chmod 777 /etc/environment
              sed -i '/scripts-user/c\ - [scripts-user, always]' /etc/cloud/cloud.cfg
              cd /var/lib/cloud/scripts/per-boot/
              touch updateenv.sh
              cat > /var/lib/cloud/scripts/per-boot/updateenv.sh << 'EOL'
                sudo pm2 reload all --update-env
              EOL
              cat > /etc/environment << 'EOL'
                export DB_ADDRESS=${aws_db_instance.rds_instance.address}
                export AWS_BUCKET_NAME=${aws_s3_bucket.private_bucket.id}
                export AWS_BUCKET_REGION=${aws_s3_bucket.private_bucket.region}
                export DB_NAME=${var.db_name}
                export DB_PASSWORD=${var.db_password}
                export DB_USER_NAME=${var.db_name}
              EOL
              source /etc/profile
              cd /home/ec2-user/webapp
              rm -rf node_modules
              sudo npm install
              sudo systemctl enable webapp
              sudo systemctl start webapp
              sudo pm2 reload all --update-env
              EOF
}

resource "aws_security_group" "database_sg" {
  name_prefix = "my_database_security_group"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.application_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/8"] # Restrict access to the instance from the internet
  }
}

resource "random_id" "random" {
  byte_length = 8
  prefix      = "prefix-"
}

resource "aws_s3_bucket" "private_bucket" {
  bucket = "my-private-bucket-${random_id.random.hex}"
  acl    = "private"

  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "private_bucket_server_side_encryption_configuration" {
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }

  bucket = aws_s3_bucket.private_bucket.id
}

resource "aws_s3_bucket_lifecycle_configuration" "private_bucket_lifecycle_configuration" {
  rule {
    id     = "transition-to-standard-ia"
    status = "Enabled"
    prefix = ""

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }

  bucket = aws_s3_bucket.private_bucket.id
}

resource "aws_s3_bucket_public_access_block" "private_bucket_block" {
  bucket                  = aws_s3_bucket.private_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_policy" "webapp_s3_policy" {
  name = "WebAppS3"
  path = "/"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.private_bucket.arn}",
          "${aws_s3_bucket.private_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role" "ec2_role" {
  name = "EC2-CSYE6225"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "webapp_s3_attachment" {
  policy_arn = aws_iam_policy.webapp_s3_policy.arn
  role       = aws_iam_role.ec2_role.name
}

resource "aws_db_parameter_group" "postgres" {
  name_prefix = "postgres"
  family      = "postgres13"

  parameter {
    name  = "log_connections"
    value = "1"
  }
}

resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "my_rds_subnet_group"
  subnet_ids = aws_subnet.private_subnet.*.id
}

resource "aws_db_instance" "rds_instance" {
  identifier             = "csye6225"
  engine                 = "postgres"
  engine_version         = "13"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  name                   = var.db_name
  username               = var.db_name
  password               = var.db_password
  parameter_group_name   = aws_db_parameter_group.postgres.name
  publicly_accessible    = false
  multi_az               = false
  skip_final_snapshot    = true
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.database_sg.id]
}

data "aws_route53_zone" "profile" {
  name = "${var.domain_profile}.${var.domain}"
}

resource "aws_route53_record" "example" {
  zone_id = data.aws_route53_zone.profile.zone_id
  name    = "${var.domain_profile}.${var.domain}"
  type    = "A"
  ttl     = "300"
  records = [aws_instance.webserver.public_ip]
}