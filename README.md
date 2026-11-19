# Linux EC2 web server with Terraform

Deploy one Amazon Linux 2023 `t3.micro` instance in a VPC with a public subnet
and an internet gateway. On first boot, `user_data.sh` installs Nginx and
publishes a static page. The security group exposes HTTP (port 80) but not SSH.
This is a demo, not an HTTPS deployment.

## Deploy

You need Terraform 1.6 or later, `curl`, and AWS credentials with permission to
manage EC2 and VPC resources and read the public AMI parameter in Systems
Manager. AWS can charge for the instance, its storage, and its public IPv4
address.

From the repository directory, run:

```sh
terraform init
terraform fmt -check
terraform validate
terraform plan -out=webserver.tfplan
terraform apply webserver.tfplan
```

The default region is `us-east-1`. To deploy elsewhere, add
`-var='aws_region=YOUR_REGION'` to `terraform plan`.

## Test the webpage

Allow a few minutes after `terraform apply` for Nginx installation to finish,
then run:

```sh
url="$(terraform output -raw web_url)"
curl --fail --show-error --silent --max-time 10 "$url" | grep -F '<h1>Terraform EC2 Web Server</h1>'
```

The command should print the matching heading. You can also open the `web_url`
in a browser. If the check fails immediately after deployment, wait briefly
and try again.

## Clean up

From the same directory and with the same Terraform state, run
`terraform destroy` and confirm the deletion. If you set a different region
when planning, pass the same `-var='aws_region=YOUR_REGION'` to `terraform destroy`.
