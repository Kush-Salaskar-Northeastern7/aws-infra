# aws-infra
This Terraform template is designed to create multiple Virtual Private Clouds (VPCs) in an AWS environment, each with its own set of public and private subnets. The template can be used to quickly provision the necessary networking resources for your infrastructure, and to ensure that each VPC has a unique network address space and subnets.

## Prerequisites
- Terraform installed on your local machine. You can download it from the official Terraform website.
- An AWS account with sufficient permissions to create VPCs, subnets, internet gateways, and route tables.
- An AWS CLI profile with the necessary credentials to access your AWS account.

## Usage
Clone this repository to your local machine:

```
git clone git@github.com:SPRING2023-CSYE6225/aws-infra.git
```

Change into the repository directory:

```
cd aws-infra/modules
```

Create a <b>terraform.tfvars</b> and add the values as below:

```
region              = "us-east-1"
profile             = "dev"
vpc_cidr            = "10.0.0.0/16"
public_subnet_cidr  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnet_cidr = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
availability_zones  = ["us-east-1a", "us-east-1b", "us-east-1c"]
```

Initialize terraform:

```
terraform init
```

Preview the changes Terraform will make:

```
terraform plan
```

Apply the Terraform configuration:

```
terraform apply
```

When prompted, enter yes to confirm the creation of the VPCs and related resources.


## Cleanup

To remove the VPCs and related resources created by this template, run the following command:

```
terraform destroy
```

When prompted, enter yes to confirm the deletion of the resources.