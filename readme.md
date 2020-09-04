# Terraform training

This repo is for my Terraform training. <br>

## Prerequisites

1. Download terraform and add to path: https://www.terraform.io/downloads.html <br>
    1.1 You can verify that terraform works by running command `terraform version` at cmd.
2. AWS Account with admin access.

## How to deploy the configuration?

1. Fill the blanks from config.txt
2. Change the name of the config.txt to config.tfvars.
3. Run `terraform init` to download providers.
4. Run `terraform plan -out config.tfplan -var-file=config.tfvars` to plan the changes.
5. Run `terraform apply "config.tfplan"` to deploy the plan.

## How to destroy the configuration?

1. Fill the blanks from config.txt
2. Change the name of the config.txt to config.tfvars.
3. Run `terraform destroy -var-file=config.tfvars` to destroy all configurations.

## How to validate the configuration?

1. Fill the blanks from config.txt
2. Change the name of the config.txt to config.tfvars.
3. Run `terraform init` to download providers.
4. Run `Terraform validate` to check syntax of the files.<br>
    4.1 <strong>NOTE!</strong> Validation doesn't check if the configuration is actually correct. Just the syntax.
