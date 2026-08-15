# Getting Started

This guide walks through deploying the OpenVPN module for the first time.

## Prerequisites

- **Terraform** `~> 1.5`
- **AWS provider** `~> 6.0` (AWS 5.x is not supported)
- **Google provider** `~> 6.0`
- An existing **VPC** with:
    - **Private (backend) subnets** for the OpenVPN instances and portal tasks
    - **Public (load balancer) subnets** for the Network Load Balancer
- A **Route 53 hosted zone** for the domain you will serve the VPN and portal from
- An **IAM role ARN** that is allowed to update the Google OAuth secret in Secrets Manager
- A second AWS **region** for cross-region replication of the portal access-log bucket
  (must differ from the deploy region)

## Provider configuration

The module requires two AWS provider configurations: the default `aws` provider for resources, and
an `aws.dns` aliased provider for Route 53 records. They can point at the same account/region, or
`aws.dns` can target the account that owns the hosted zone.

```hcl
provider "aws" {
  region = "us-west-2"
}

# DNS provider — same account here, but can target a different DNS account.
provider "aws" {
  alias  = "dns"
  region = "us-west-2"
}
```

## Minimal deployment

```hcl
data "aws_route53_zone" "this" {
  name = "example.com"
}

module "openvpn" {
  source  = "registry.infrahouse.com/infrahouse/openvpn/aws"
  version = "10.1.0"
  providers = {
    aws     = aws
    aws.dns = aws.dns
    google  = google
  }

  environment                = "production"
  alarm_emails               = ["alerts@example.com"]
  backend_subnet_ids         = var.private_subnet_ids
  lb_subnet_ids              = var.public_subnet_ids
  zone_id                    = data.aws_route53_zone.this.zone_id
  google_oauth_client_writer = data.aws_iam_role.admin.arn
  replication_region         = "us-east-1"
}
```

Apply it:

```bash
terraform init
terraform plan
terraform apply
```

## Google setup

This module authenticates users with Google (portal OAuth) and revokes certificates of deactivated
Workspace users (keyless WIF), so it always needs Google configured — the OAuth client, the `google`
provider credentials (laptop and CI), and a one-time domain-wide-delegation step. It is all in one
place: **[Configuration → Google configuration](configuration.md#google-configuration)**.

## Connecting

1. Browse to `https://openvpn-portal.<your-domain>`.
2. Sign in with a Google account from an allowed domain.
3. Download the generated `.ovpn` profile.
4. Import it into your OpenVPN client and connect.

## Worked example: deploying step by step

The sections above are the quick reference. What follows is a full worked
example — with screenshots — deploying a VPN server for InfraHouse from an empty
branch through to a working connection.

### **Step 1**: Create Terraform configuration

```hcl
module "vpn" {
  source  = "registry.infrahouse.com/infrahouse/openvpn/aws"
  version = "10.1.0"

  providers = {
    aws     = aws
    aws.dns = aws
    google  = google
  }

  backend_subnet_ids         = module.management.subnet_private_ids
  lb_subnet_ids              = module.management.subnet_public_ids
  google_oauth_client_writer = tolist(data.aws_iam_roles.sso-admin.arns)[0]
  zone_id                    = module.infrahouse_com.infrahouse_zone_id
  allowed_domains            = [
    # "infrahouse.com",  <- implicitly derived from module.infrahouse_com.infrahouse_zone_id
    "foo.com"
  ]
}

data "aws_iam_roles" "sso-admin" {
  name_regex  = "AWSReservedSSO_AWSAdministratorAccess_.*"
  path_prefix = "/aws-reserved/sso.amazonaws.com/"
}
```
Our VPN setup will consist of two components: the OpenVPN server and the OpenVPN Portal.

OpenVPN server: Deployed in an Auto Scaling group fronted by a Network Load Balancer.

![openvp-server](https://raw.githubusercontent.com/infrahouse/terraform-aws-openvpn/main/assets/openvp-server.drawio.png)

OpenVPN Portal: A web application deployed as an AWS ECS service. 
It authenticates users via Google and distributes OpenVPN profiles.

![openvp-portal](https://raw.githubusercontent.com/infrahouse/terraform-aws-openvpn/main/assets/openvp-portal.drawio.png)

All module variables shown above are required, except `allowed_domains`:

* `backend_subnet_ids`. A list of subnet IDs for the EC2 instances in the Auto Scaling group (private subnets).
* `lb_subnet_ids`. A list of subnet IDs for the Network Load Balancer (public subnets).  
* `google_oauth_client_writer`. The IAM role ARN permitted to update the Google OAuth client secret.
* `zone_id`. The Route 53 zone ID (e.g., infrahouse.com) for DNS records.
* `providers` Separate providers for AWS and Route 53 (`aws.dns`). 
`aws.dns` is responsible for creating Route53 resources and the default `aws` provider does the rest. In our case, 
the VPN and infrahouse.com live in the same AWS account. so the providers are the same.
* `allowed_domains` (optional). A list of domain names whose users are permitted to connect to the VPN server. 
The module will automatically include the domain specified by `zone_id`.

### **Step 2**: Create a pull request

This is a commit.
```
$ git log -p -1
commit b695867f71846a1e7d2fabf14e21cebd2b026516 (HEAD -> vpn)
Author: Oleksandr Kuzminskyi <aleksandr.kuzminsky@gmail.com>
Date:   Fri Jul 5 11:35:18 2024 -0700

    Deploy VPN

diff --git a/vpn.tf b/vpn.tf
new file mode 100644
index 0000000..035b925
--- /dev/null
+++ b/vpn.tf
@@ -0,0 +1,16 @@
+module "vpn" {
+  source  = "registry.infrahouse.com/infrahouse/openvpn/aws"
+  version = "10.1.0"
+  providers = {
+    aws     = aws
+    aws.dns = aws
+    google  = google
+  }
+  backend_subnet_ids         = module.management.subnet_private_ids
+  lb_subnet_ids              = module.management.subnet_public_ids
+  google_oauth_client_writer = data.aws_iam_role.AWSAdministratorAccess.arn
+  zone_id                    = module.infrahouse_com.infrahouse_zone_id
+}
+
+data "aws_iam_role" "AWSAdministratorAccess" {
+  name = "AWSReservedSSO_AWSAdministratorAccess_a84a03e62f490b50"
+}
```
Create the PR:
```shell
$ gh pr create
? Where should we push the 'vpn' branch? infrahouse/aws-control-493370826424

Creating pull request for vpn into main in infrahouse/aws-control-493370826424

? Title Deploy VPN
? Body <Received>
? What's next? Submit
remote:
remote:
To github.com:infrahouse/aws-control-493370826424.git
 * [new branch]      HEAD -> vpn
Branch 'vpn' set up to track remote branch 'vpn' from 'origin'.
https://github.com/infrahouse/aws-control-493370826424/pull/199
```
Now, the [pull request](https://github.com/infrahouse/aws-control-493370826424/pull/199) successfully ran `terraform plan` 
and we can review the plan output to ensure no unexpected changes.

![terraform-plan.png](https://raw.githubusercontent.com/infrahouse/terraform-aws-openvpn/main/assets/terraform-plan.png)

By default, the module provisions around 80 resources. 
In your deployment, each resource address should be prefixed with `module.vpn`, 
confirming that Terraform will create the expected resources. 
If your plan shows any resources to be changed or destroyed, 
review the output carefully to understand the proposed actions before applying.

![terraform-plan-stdout.png](https://raw.githubusercontent.com/infrahouse/terraform-aws-openvpn/main/assets/terraform-plan-stdout.png)

### **Step 3**: Merge the pull request.
```shell
$ gh pr merge -ds
✓ Squashed and merged pull request #199 (Deploy VPN)
remote: Enumerating objects: 1, done.
remote: Counting objects: 100% (1/1), done.
remote: Total 1 (delta 0), reused 0 (delta 0), pack-reused 0
Unpacking objects: 100% (1/1), 849 bytes | 169.00 KiB/s, done.
From github.com:infrahouse/aws-control-493370826424
 * branch            main       -> FETCH_HEAD
   efd3d98..5f28f7a  main       -> origin/main
Updating efd3d98..5f28f7a
Fast-forward
 vpn.tf | 16 ++++++++++++++++
 1 file changed, 16 insertions(+)
 create mode 100644 vpn.tf
✓ Deleted branch vpn and switched to branch main
```
[Check](https://github.com/infrahouse/aws-control-493370826424/pull/199) that Terraform successfully created the VPN resources.

![pr-deploy.png](https://raw.githubusercontent.com/infrahouse/terraform-aws-openvpn/main/assets/pr-deploy.png)

### **Step 4**: Configure Google OAuth2.0.

If you visit https://openvpn-portal.infrahouse.com/ in your browser, 
you’ll get a 502 error because the Google OAuth client credentials haven’t been set yet. 
Let’s fix that now.

![502.png](https://raw.githubusercontent.com/infrahouse/terraform-aws-openvpn/main/assets/502.png)

The module automatically creates a placeholder secret for the Google OAuth client ID. 
You can confirm this by listing secrets:

```shell
$ ih-secrets --aws-region us-west-1 --aws-profile AWSAdministratorAccess-493370826424 list | grep google
| google_client20240705183915856300000015              | A JSON with Google OAuth Client ID                                                                                        |
```

Since it’s just a placeholder, the secret has no value yet. Retrieving it returns `NoValue`:

```shell
$ ih-secrets --aws-region us-west-1 --aws-profile AWSAdministratorAccess-493370826424 get google_client20240705183915856300000015
NoValue
```
#### **Step 4.1**: Create OAuth 2.0 credentials.

Open the [Google Cloud Console](https://console.cloud.google.com/) and select (or create) your OpenVPN project.

![gc-1.png](https://raw.githubusercontent.com/infrahouse/terraform-aws-openvpn/main/assets/gc-1.png)

In the sidebar, go to **APIs & Services > Credentials**.

![gc-2.png](https://raw.githubusercontent.com/infrahouse/terraform-aws-openvpn/main/assets/gc-2.png)

Click **Create credentials > OAuth client ID**. Then configure:
* *Authorized JavaScript origins*: https://openvpn-portal.infrahouse.com
* *Authorized redirect URIs*: https://openvpn-portal.infrahouse.com/login/google/authorized 
(For your own domain, replace infrahouse.com with my-domain.com.)

![img.png](https://raw.githubusercontent.com/infrahouse/terraform-aws-openvpn/main/assets/gc-3.png)

#### **Step 4.2**: Download OAuth 2.0 credentials.

After clicking **Create**, a confirmation screen will appear with a **Download JSON** link—click 
it to download and save your credentials file.

![img.png](https://raw.githubusercontent.com/infrahouse/terraform-aws-openvpn/main/assets/gc-04.png)

#### **Step 4.3**: Update Google OAuth Client ID secret value.

From the previous step, the secret name is `google_client20240705183915856300000015`. 
Let’s populate it with your actual credentials. For reference, the JSON should look like this:
```shell
$ jq < client_secret.json
{
  "web": {
    "client_id": "145076599640-incpb6lilkj5duv3qs65n6f9r5avo482.apps.googleusercontent.com",
    "project_id": "openvpn-427715",
    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
    "token_uri": "https://oauth2.googleapis.com/token",
    "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
    "client_secret": "very-secret-string",
    "redirect_uris": [
      "https://openvpn-portal.infrahouse.com/login/google/authorized"
    ],
    "javascript_origins": [
      "https://openvpn-portal.infrahouse.com"
    ]
  }
}
```

```shell
$ ih-secrets \
  --aws-region us-west-1 \
  --aws-profile AWSAdministratorAccess-493370826424 \
  set \
  google_client20240705183915856300000015 \
  client_secret.json
```
#### **Step 4.4**: (Optional) Enable access to VPN from multiple domains.

If you plan to support VPN users from more than one domain, you need to make the OpenVPN App external.
To do that, click on *APIs & Services > OAuth consent screen > Audience* and publish the OpenVPN App.
![gc-05.png](https://raw.githubusercontent.com/infrahouse/terraform-aws-openvpn/main/assets/gc-05.png)

### **Step 5**: Check on OpenVPN Portal.

After a few moments, the portal will pick up the updated Google OAuth credentials. 
When you revisit https://openvpn-portal.infrahouse.com/, you’ll see the Google sign-in prompt. 
Once authenticated, the portal will display instructions for your OpenVPN client.

![img.png](https://raw.githubusercontent.com/infrahouse/terraform-aws-openvpn/main/assets/portal-start-page.png)

### **Step 6**: Install OpenVPN client.

The portal provides installers for macOS and Windows. 
For other operating systems, visit https://openvpn.net/client/ to download the appropriate OpenVPN client.

![img.png](https://raw.githubusercontent.com/infrahouse/terraform-aws-openvpn/main/assets/openvpn-download-page.png)

### **Step 6**: Download and import OpenVPN profile.

Once the client is installed, click on https://openvpn-portal.infrahouse.com/profile and save the OpenVPN profile 
on your laptop.

Double-click on the `aleks@infrahouse.com-openvpn.infrahouse.com.ovpn` file. It will open the client and suggest 
to import the profile.

![img.png](https://raw.githubusercontent.com/infrahouse/terraform-aws-openvpn/main/assets/import-profile-page.png)

### **Step 7**: Connect to VPN.

|                                                                                                             |    |                                |                            
|-------------------------------------------------------------------------------------------------------------|----|--------------------------------|
| ![img.png](https://raw.githubusercontent.com/infrahouse/terraform-aws-openvpn/main/assets/connect-page.png) | ➡️ | ![img.png](https://raw.githubusercontent.com/infrahouse/terraform-aws-openvpn/main/assets/connected-page.png) |


### **Step 8**: Check network connectivity with the VPN server.

The VPN server has address 172.16.0.1. Let's make sure it's reachable via the VPN.

```shell
$ ping -c 3 172.16.0.1
PING 172.16.0.1 (172.16.0.1) 56(84) bytes of data.
64 bytes from 172.16.0.1: icmp_seq=1 ttl=63 time=9.84 ms
64 bytes from 172.16.0.1: icmp_seq=2 ttl=63 time=12.8 ms
64 bytes from 172.16.0.1: icmp_seq=3 ttl=63 time=11.3 ms

--- 172.16.0.1 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2003ms
rtt min/avg/max/mdev = 9.844/11.312/12.833/1.220 ms
```
However, if we try to ping the primary interface on the OpenVPN server, it's unreachable. 

```shell
$ ih-ec2 --aws-region us-west-1 --aws-profile AWSAdministratorAccess-493370826424 list
2024-07-05 12:37:23,046: INFO: botocore.tokens:tokens._refresher():305: Loading cached SSO token for infrahouse
2024-07-05 12:37:23,656: INFO: infrahouse_toolkit.cli.ih_ec2:__init__.ih_ec2():68: Connected to AWS as arn:aws:sts::493370826424:assumed-role/AWSReservedSSO_AWSAdministratorAccess_a84a03e62f490b50/aleks
2024-07-05 12:37:23,714: INFO: botocore.tokens:tokens._refresher():305: Loading cached SSO token for infrahouse
+--------------------+---------------------+----------------+-----------------+-------------------+--------------------+---------+
| Name               | InstanceId          | InstanceType   | PublicDnsName   | PublicIpAddress   | PrivateIpAddress   | State   |
+====================+=====================+================+=================+===================+====================+=========+
...
| openvpn            | i-009c6fb01374dfa9e | m6in.large     |                 |                   | 10.0.1.244         | running |
| openvpn-portal     | i-057151311f6ee0621 | t3.small       |                 |                   | 10.0.1.104         | running |
+--------------------+---------------------+----------------+-----------------+-------------------+--------------------+---------+
```

```shell
$ ping -c 3 10.0.1.244
PING 10.0.1.244 (10.0.1.244) 56(84) bytes of data.

--- 10.0.1.244 ping statistics ---
3 packets transmitted, 0 received, 100% packet loss, time 2092ms
```

This happens because we haven’t told the VPN client which networks it should route through the tunnel.


### **Step 9**: Add routes to the VPN client.

To allow VPN clients to reach the InfraHouse cloud management network, 
let’s update the module configuration.
```shell
$ git log -p -1
commit d3c4f50dd8d427ab25ba30cadccd328bc1def7d3 (HEAD -> vpn, origin/vpn)
Author: Oleksandr Kuzminskyi <aleksandr.kuzminsky@gmail.com>
Date:   Fri Jul 5 12:32:00 2024 -0700

    Add VPN routes

diff --git a/vpn.tf b/vpn.tf
index 035b925..83fe71f 100644
--- a/vpn.tf
+++ b/vpn.tf
@@ -9,6 +9,12 @@ module "vpn" {
   lb_subnet_ids              = module.management.subnet_public_ids
   google_oauth_client_writer = data.aws_iam_role.AWSAdministratorAccess.arn
   zone_id                    = module.infrahouse_com.infrahouse_zone_id
+  routes = [
+    {
+      network : cidrhost(module.management.vpc_cidr_block, 0)
+      netmask : cidrnetmask(module.management.vpc_cidr_block)
+    }
+  ]
 }

 data "aws_iam_role" "AWSAdministratorAccess" {
```

Create a [pull request](https://github.com/infrahouse/aws-control-493370826424/pull/200), get it merged,
and make sure it's successfully applied.

### **Step 10**: Check network availability of instances beyond the VPN server.

Applying the Terraform changes triggers an Auto Scaling instance refresh for the OpenVPN servers, 
which can take 5–10 minutes. The OpenVPN client will automatically reconnect 
to the new instances once they’re ready. After that, verify connectivity 
by pinging the private IP addresses in your VPC.

```shell
$ ih-ec2 --aws-region us-west-1 --aws-profile AWSAdministratorAccess-493370826424 list | grep openvpn
| openvpn            | i-04933b6fb1a9ae7c8 | m6in.large     |                 |                   |                    | terminated |
| openvpn            | i-08705597ae7457604 | m6in.large     |                 |                   |                    | terminated |
| openvpn            | i-00ecc4e72166d9ef0 | m6in.large     |                 |                   | 10.0.3.144         | running    |
| openvpn            | i-009c6fb01374dfa9e | m6in.large     |                 |                   |                    | terminated |
| openvpn            | i-082016a9399b155f6 | m6in.large     |                 |                   | 10.0.1.245         | running    |
| openvpn-portal     | i-057151311f6ee0621 | t3.small       |                 |                   | 10.0.1.104         | running    |
```

```shell
$ ping  -c 1 10.0.3.144
PING 10.0.3.144 (10.0.3.144) 56(84) bytes of data.
64 bytes from 10.0.3.144: icmp_seq=1 ttl=62 time=63.1 ms

--- 10.0.3.144 ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 63.058/63.058/63.058/0.000 ms
```

```shell
$ ping  -c 1 10.0.1.104
PING 10.0.1.104 (10.0.1.104) 56(84) bytes of data.
64 bytes from 10.0.1.104: icmp_seq=1 ttl=253 time=7.29 ms

--- 10.0.1.104 ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 7.285/7.285/7.285/0.000 ms
```

## Next steps

- Review every input in the [Configuration](configuration.md) reference.
- See [Examples](examples.md) for multi-domain, custom-routes, and scaling setups.
- Keep [Troubleshooting](troubleshooting.md) handy for first-connection issues.
