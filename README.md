# Linux EC2 web server with Terraform

Deploy one Amazon Linux 2023 `t3.micro` instance in a new subnet in an approved
existing VPC. Terraform associates the subnet with an existing public route
table and does not create or modify any routes or internet gateways. On first
boot, `user_data.sh` installs Nginx and publishes a static page. The security
group exposes HTTP (port 80) but not SSH. This is a demo, not an HTTPS deployment.

## Prerequisites

- Terraform 1.6 or later, AWS CLI v2, and a Bash shell such as Git Bash.
- AWS credentials for the target account. To find values with the helper
  script, they need `ec2:DescribeRouteTables`, `ec2:DescribeVpcs`, and
  `ec2:DescribeSubnets`. To deploy, they also need permission to read the
  public AMI parameter in Systems Manager, create a subnet and associate it
  with the route table, create a security group, and launch EC2 with a public
  IPv4 address.
- Approval from the VPC owner to add a subnet to the VPC, associate it with
  the route table, and allow public HTTP for the demo.

AWS can charge for the instance, its storage, and its public IPv4 address.

## Values to replace

The commands below use three placeholders. Replace only the text inside the
quotes; keep the quotes.

| Placeholder | Replace with | Where to get it | Example |
|---|---|---|---|
| `REPLACE_WITH_AWS_REGION` | AWS region to deploy in | Your approved region | `ap-south-1` |
| `REPLACE_WITH_ROUTE_TABLE_ID` | Public route table ID | `ROUTE TABLE ID` column in step 1 | `rtb-0123456789abcdef0` |
| `REPLACE_WITH_SUBNET_CIDR` | Unused subnet range | One `AVAILABLE SUBNET CIDR` in step 1 | `10.0.2.0/24` |

The examples are illustrative; do not copy them unless they match your
step 1 output.

## 1. Find a public route table and an available subnet CIDR

From the repository directory in Bash, set your region and run the helper:

```sh
AWS_REGION='REPLACE_WITH_AWS_REGION'   # for example: 'ap-south-1'
bash route_table_cidr.sh "$AWS_REGION"
```

The script is read-only. It lists only route tables with an **active**
`0.0.0.0/0` route to an internet gateway. Private route tables, which have
only the VPC `local` route, and routes to missing or detached gateways are
omitted. It also shows each internet gateway ID and the number of VPCs with
such a route.

Enter a listed route table ID when prompted. The script prints the VPC ID,
route table ID, existing subnet CIDRs, and up to five available `/24` subnet
CIDRs inside the VPC:

```text
VPC ID                   ROUTE TABLE ID           AVAILABLE SUBNET CIDR
vpc-0123456789abcdef0    rtb-0123456789abcdef0    10.0.0.0/24
vpc-0123456789abcdef0    rtb-0123456789abcdef0    10.0.2.0/24
```

Use these values in the next step:

- Copy the `ROUTE TABLE ID` value, which starts with `rtb-`, into
  `ROUTE_TABLE_ID`.
- Copy one `AVAILABLE SUBNET CIDR` value, such as `10.0.2.0/24`, into
  `SUBNET_CIDR`. Do not use the VPC's own CIDR, such as `10.0.0.0/16`; it
  overlaps any existing subnet.

The results reflect the VPC at the time the script runs. If someone creates an
overlapping subnet before you apply, rerun the script and choose another
available CIDR. The VPC must provide DNS resolution. Its network ACL must
allow inbound HTTP, outbound HTTPS for package downloads, and the return
traffic for both.

## 2. Plan the deployment

In the **same Bash terminal** as step 1, replace the two placeholders below
with your values from step 1. `AWS_REGION` is already set; if you opened a new
terminal, set it again first.

```sh
ROUTE_TABLE_ID='REPLACE_WITH_ROUTE_TABLE_ID'   # for example: 'rtb-0123456789abcdef0'
SUBNET_CIDR='REPLACE_WITH_SUBNET_CIDR'         # for example: '10.0.2.0/24'
```

Then run these commands as-is. They do not need editing:

```sh
terraform init
terraform fmt -check
terraform validate
terraform plan -out=webserver.tfplan \
  -var="aws_region=$AWS_REGION" \
  -var="public_route_table_id=$ROUTE_TABLE_ID" \
  -var="subnet_cidr_block=$SUBNET_CIDR"
```

Always use the region you searched in step 1; without `aws_region`,
Terraform uses `us-east-1`. If the plan reports that the route table needs an
IPv4 default route to an internet gateway, rerun step 1 in the same region and
choose a listed table.

## 3. Review and apply

Review the plan before applying. If you previously deployed the version that
created its own VPC, route table, and gateway, those resources may be scheduled
for deletion. Stop if that cleanup is not intended. For a fresh deployment,
the plan should only add the subnet, its route-table association, the security
group, and the instance.

```sh
terraform apply webserver.tfplan
```

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
`terraform destroy` with the **same three values used for `terraform plan`**.
If you are in a new terminal, set them again first:

```sh
AWS_REGION='REPLACE_WITH_AWS_REGION'           # same value as step 1
ROUTE_TABLE_ID='REPLACE_WITH_ROUTE_TABLE_ID'   # same value as step 2
SUBNET_CIDR='REPLACE_WITH_SUBNET_CIDR'         # same value as step 2
```

Then run this command as-is:

```sh
terraform destroy \
  -var="aws_region=$AWS_REGION" \
  -var="public_route_table_id=$ROUTE_TABLE_ID" \
  -var="subnet_cidr_block=$SUBNET_CIDR"
```

Review the deletions before typing `yes`. Terraform should remove only the
instance, security group, route-table association, and subnet that it created.
The existing VPC, route table, and internet gateway are not managed by this
configuration.
