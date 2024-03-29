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
    from_port   = 3001
    to_port     = 3001
    protocol    = "tcp"
    security_groups = [aws_security_group.load_balancer_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_key_pair" "my_key_pair" {
  key_name   = "my-key-pair-name"
  public_key = file("~/.ssh/id_ed25519_Uni.pub")
}

resource "aws_launch_template" "asg_launch_template" {
  name                 = "asg_launch_template"
  image_id             = var.ami_id
  instance_type        = "t2.micro"
  key_name             = aws_key_pair.my_key_pair.key_name
  disable_api_termination = false
  ebs_optimized        = false
  metadata_options {
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
    http_tokens                 = "required"
  }
  network_interfaces {
    associate_public_ip_address = true
    delete_on_termination       = true
    security_groups = ["${aws_security_group.application_sg.id}"]
  }
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 50
      volume_type = "gp2"
      delete_on_termination = true
      encrypted = true
      kms_key_id = aws_kms_key.ebs_key.arn 
    }
  }
  user_data = base64encode(<<-EOF
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
              sudo pm2 startOrReload ecosystem.config.js
              sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/home/ec2-user/webapp/amazonCloudwatchConfig.json -s
              EOF
              )
  # iam_instance_profile = aws_iam_instance_profile.webapp_instance_profile.arn
  iam_instance_profile {
    arn = aws_iam_instance_profile.webapp_instance_profile.arn
  }
  # vpc_security_group_ids = [aws_security_group.application_sg.id]
}

# resource "aws_launch_configuration" "asg_launch_config" {
#   name                 = "asg_launch_config"
#   image_id             = var.ami_id
#   instance_type        = "t2.micro"
#   # key_name             = var.key_name
#   associate_public_ip_address = true
#   root_block_device {
#     volume_size           = 50
#     volume_type           = "gp2"
#     delete_on_termination = true
#   }
#   user_data = <<-EOF
#               #!/bin/bash
#               yum update -y
#               chmod 777 /etc/environment
#               sed -i '/scripts-user/c\ - [scripts-user, always]' /etc/cloud/cloud.cfg
#               cd /var/lib/cloud/scripts/per-boot/
#               touch updateenv.sh
#               cat > /var/lib/cloud/scripts/per-boot/updateenv.sh << 'EOL'
#                 sudo pm2 reload all --update-env
#               EOL
#               cat > /etc/environment << 'EOL'
#                 export DB_ADDRESS=${aws_db_instance.rds_instance.address}
#                 export AWS_BUCKET_NAME=${aws_s3_bucket.private_bucket.id}
#                 export AWS_BUCKET_REGION=${aws_s3_bucket.private_bucket.region}
#                 export DB_NAME=${var.db_name}
#                 export DB_PASSWORD=${var.db_password}
#                 export DB_USER_NAME=${var.db_name}
#               EOL
#               source /etc/profile
#               cd /home/ec2-user/webapp
#               rm -rf node_modules
#               sudo npm install
#               sudo systemctl enable webapp
#               sudo systemctl start webapp
#               sudo pm2 reload all --update-env
#               sudo pm2 startOrReload ecosystem.config.js
#               sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/home/ec2-user/webapp/amazonCloudwatchConfig.json -s
#               EOF
#   iam_instance_profile = aws_iam_instance_profile.webapp_instance_profile.name
#   security_groups      = [aws_security_group.application_sg.id]
# }

resource "aws_autoscaling_group" "asg" {
  name                 = "webapp_asg"
  # launch_template { 
  #   id = "${aws_launch_template.asg_launch_template.id}" 
  #   version = "${aws_launch_template.asg_launch_template.latest_version}" 
  # }
  launch_template {
    id      = aws_launch_template.asg_launch_template.id
    version = "$Latest"
  }
  # launch_configuration = aws_launch_configuration.asg_launch_config.id
  # cooldown             = 60
  min_size             = 1
  max_size             = 3
  desired_capacity     = 1
  health_check_grace_period = 60
  health_check_type = "EC2"
  target_group_arns = [ aws_lb_target_group.web.arn ]
  # availability_zones = var.availability_zones
  vpc_zone_identifier = aws_subnet.public_subnet.*.id
  tag {
    key                 = "Name"
    value               = "webapp"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "webapp_scale_up_policy" {
    name                    = "webapp_scale_up_policy"
    adjustment_type         = "ChangeInCapacity"
    # scaling_adjustment      = 1
    # cooldown                = 60
    policy_type             = "TargetTrackingScaling"
    target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 5.0
  }
    
    autoscaling_group_name = aws_autoscaling_group.asg.name
}

resource "aws_autoscaling_policy" "webapp_scale_down_policy" {
    name                    = "webapp_scale_down_policy"
    adjustment_type         = "ChangeInCapacity"
    # scaling_adjustment      = -1
    # cooldown                = 60
    policy_type             = "TargetTrackingScaling"
    target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 3.0
  } 
    autoscaling_group_name = aws_autoscaling_group.asg.name
}

# resource "aws_cloudwatch_metric_alarm" "up_alarm" {
#   alarm_name          = "cloudwatch_scale_up_alarm"
#   comparison_operator = "GreaterThanThreshold"
#   evaluation_periods  = 1
#   metric_name         = "CPUUtilization"
#   namespace           = "AWS/EC2"
#   period              = 60
#   statistic           = "Average"
#   threshold           = 5

#   alarm_description = "This metric monitors ec2 high cpu utilization"
#   alarm_actions     = [aws_autoscaling_policy.webapp_scale_up_policy.arn]
# }

# resource "aws_cloudwatch_metric_alarm" "down_alarm" {
#   alarm_name          = "cloudwatch_scale_down_alarm"
#   comparison_operator = "LessThanThreshold"
#   evaluation_periods  = 1
#   metric_name         = "CPUUtilization"
#   namespace           = "AWS/EC2"
#   period              = 60
#   statistic           = "Average"
#   threshold           = 3

#   alarm_description = "This metric monitors ec2 low cpu utilization"
#   alarm_actions     = [aws_autoscaling_policy.webapp_scale_down_policy.arn]
# }

resource "aws_lb" "web-alb" {
  name               = "web-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.load_balancer_sg.id]
  subnets            = aws_subnet.public_subnet.*.id

  tags = {
    Name = "web-alb"
  }
}

resource "aws_lb_target_group" "web" {
  name_prefix       = "webtg-"
  port              = 3001
  protocol          = "HTTP"
  vpc_id            = aws_vpc.vpc.id
  ip_address_type   = "ipv4"
  target_type       = "instance"
  health_check {
    protocol     = "HTTP"
    path         = "/healthz"
    port         = 3001
    interval     = 90
    timeout      = 60
    healthy_threshold = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "web-alb-target-group"
  }
}

resource "aws_lb_listener" "lb_listener" {
  load_balancer_arn = aws_lb.web-alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "arn:aws:acm:us-east-1:562694632201:certificate/7563dd81-84d5-49e1-a166-65543f9bc3c0"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

resource "aws_iam_instance_profile" "webapp_instance_profile" {
  name = "webapp_instance_profile"
  role = aws_iam_role.ec2_role.name
}

# resource "aws_instance" "webserver" {
#   ami                         = var.ami_id
#   instance_type               = "t2.micro"
#   vpc_security_group_ids      = [aws_security_group.application_sg.id]
#   subnet_id                   = aws_subnet.public_subnet[0].id
#   associate_public_ip_address = true
#   root_block_device {
#     volume_size           = 50
#     volume_type           = "gp2"
#     delete_on_termination = true
#   }
#   tags = {
#     Name = "webserver"
#   }
#   iam_instance_profile = aws_iam_instance_profile.webapp_instance_profile.name
#   # Disable termination protection
#   disable_api_termination = true

  # user_data = <<-EOF
  #             #!/bin/bash
  #             yum update -y
  #             chmod 777 /etc/environment
  #             sed -i '/scripts-user/c\ - [scripts-user, always]' /etc/cloud/cloud.cfg
  #             cd /var/lib/cloud/scripts/per-boot/
  #             touch updateenv.sh
  #             cat > /var/lib/cloud/scripts/per-boot/updateenv.sh << 'EOL'
  #               sudo pm2 reload all --update-env
  #             EOL
  #             cat > /etc/environment << 'EOL'
  #               export DB_ADDRESS=${aws_db_instance.rds_instance.address}
  #               export AWS_BUCKET_NAME=${aws_s3_bucket.private_bucket.id}
  #               export AWS_BUCKET_REGION=${aws_s3_bucket.private_bucket.region}
  #               export DB_NAME=${var.db_name}
  #               export DB_PASSWORD=${var.db_password}
  #               export DB_USER_NAME=${var.db_name}
  #             EOL
  #             source /etc/profile
  #             cd /home/ec2-user/webapp
  #             rm -rf node_modules
  #             sudo npm install
  #             sudo systemctl enable webapp
  #             sudo systemctl start webapp
  #             sudo pm2 reload all --update-env
  #             sudo pm2 startOrReload ecosystem.config.js
  #             sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/home/ec2-user/webapp/amazonCloudwatchConfig.json -s
  #             EOF
# }

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

resource "aws_security_group" "load_balancer_sg" {
  name_prefix = "load-balancer-sg"
  description = "Security group for the load balancer to access the web application"

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

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  vpc_id      = aws_vpc.vpc.id
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
  managed_policy_arns = ["arn:aws:iam::aws:policy/CloudWatchAgentAdminPolicy"]
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
  depends_on = [
    aws_kms_key.rds_key
  ]
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
  storage_encrypted      = true
  kms_key_id             = aws_kms_key.rds_key.arn
}

data "aws_route53_zone" "profile" {
  name = "${var.domain_profile}.${var.domain}"
}

resource "aws_route53_record" "example" {
  zone_id = data.aws_route53_zone.profile.zone_id
  name    = "${var.domain_profile}.${var.domain}"
  type    = "A"
  alias {
    name                   = aws_lb.web-alb.dns_name
    zone_id                = aws_lb.web-alb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_cloudwatch_log_group" "error_group" {
  name = "app-error"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_stream" "error_stream" {
  name = "app-error-stream"
  log_group_name = aws_cloudwatch_log_group.error_group.name
}

resource "aws_cloudwatch_log_group" "output_group" {
  name = "app-output"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_stream" "output_stream" {
  name = "app-output-stream"
  log_group_name = aws_cloudwatch_log_group.output_group.name
}


data "aws_caller_identity" "current" {}

output "aws_account_id" {
  value = data.aws_caller_identity.current.account_id
}

# locals {
#   stack_name = replace(
#     "${element(split("/", var.terraform_state), -1)}",
#     ".tfstate",
#     ""
#   )
# }

# output "stack_name" {
#   value = local.stack_name
# }

resource "aws_kms_key" "ebs_key" {
  description         = "Customer managed EBS Key"
  enable_key_rotation = true
  policy              = jsonencode({
    Version = "2012-10-17"
    Id      = "ebskey"
    Statement = [
      {
        Effect    = "Allow"
        Principal = {
          # AWS = format("arn:aws:iam::%s:root", var.aws_account_id)
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Effect    = "Allow"
        Principal = {
          AWS = [
            # format("arn:aws:iam::%s:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling", var.aws_account_id)
            "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
          ]
        }
        Action    = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource  = "*"
      },
      {
        Effect    = "Allow"
        Principal = {
          AWS = [
            # format("arn:aws:iam::%s:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling", var.aws_account_id)
            "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
          ]
        }
        Action    = "kms:CreateGrant"
        Resource  = "*"
        Condition = {
          Bool = {
            "kms:GrantIsForAWSResource" = true
          }
        }
      }
    ]
  })
  deletion_window_in_days = 7
  tags = {
    Name = "terraform-ebs-key"
  }
}

resource "aws_kms_alias" "ebs_key_alias" {
  name          = "alias/ebskey"
  target_key_id = aws_kms_key.ebs_key.key_id
}

resource "aws_kms_key" "rds_key" {
  description         = "Customer managed RDS Key"
  enable_key_rotation = true
  policy              = jsonencode({
    Version = "2012-10-17"
    Id      = "rdskey"
    Statement = [
      {
        Effect    = "Allow"
        Principal = {
          # AWS = format("arn:aws:iam::%s:root", var.aws_account_id)
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action    = "kms:*"
        Resource  = "*"
      }
    ]
  })
  deletion_window_in_days = 7
  tags = {
    Name = "terraform-rds-key"
  }
}

resource "aws_kms_alias" "rds_key_alias" {
  name          = "alias/rdskey"
  target_key_id = aws_kms_key.rds_key.key_id
}

