# terraform-aws-openvpn

The [openvpn module](https://registry.terraform.io/modules/infrahouse/openvpn/aws/latest) deploys 
an OpenVPN server with Google OAuth 2.0 authentication.

Starting with version 4.0.0, the module supports VPN users from multiple Google domains.

![OpenVPN diagram](https://raw.githubusercontent.com/infrahouse/terraform-aws-openvpn/main/assets/openvpn.drawio.png)

The OpenVPN Portal is a web application that authenticates users via their Google accounts 
and generates an OpenVPN profile for them.

You should place the OpenVPN server in public subnets in your AWS environment 
so authorized users can access resources in private subnets.

## Installation

To illustrate how to use the module, we will deploy a VPN server for InfraHouse.

### **Step 1**: Create Terraform configuration

```hcl
module "vpn" {
  source  = "registry.infrahouse.com/infrahouse/openvpn/aws"
  version = "4.5.0"

  providers = {
    aws     = aws
    aws.dns = aws
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
+  version = "4.5.0"
+  providers = {
+    aws     = aws
+    aws.dns = aws
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
![gc-05.png](assets/gc-05.png)

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
| ![img.png](https://raw.githubusercontent.com/infrahouse/terraform-aws-openvpn/main/assets/connect-page.png) | ➡️ | ![img.png](connected-page.png) |


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

## Logging and Compliance

The module provides comprehensive logging for audit trail and ISO 27001 compliance requirements.

### Logging Architecture

The module captures three layers of logging:

#### 1. OpenVPN Application Logs (Recommended - In Progress)
**What it captures:**
- User authentication events (who connected, when, from where)
- Connection duration and session details
- Bytes transferred per user
- Certificate/credential validation
- Connection failures and security events

**Where:**
- CloudWatch Logs: `/aws/openvpn/<service_name>`
- Retention: Configurable via `cloudwatch_log_retention_days` (default: 365 days)

**Why it matters:**
This is your primary audit trail for **user access control** - required for ISO 27001 compliance. These logs prove who accessed your infrastructure and when.

#### 2. ECS Portal Logs (Configured)
**What it captures:**
- Portal application logs
- User authentication via Google OAuth
- Profile generation events
- Application errors

**Where:**
- CloudWatch Logs: Managed by ECS module
- Retention: Controlled by `cloudwatch_log_retention_days` variable

#### 3. VPC Flow Logs (External - Recommended)
**What it captures:**
- Network-level connection metadata
- Source/destination IPs and ports
- Bytes transferred
- Accept/reject decisions

**Where:**
- Managed separately via VPC configuration
- Recommend sending to both CloudWatch Logs (for queries) and S3 (for long-term retention)

**Why it matters:**
Network-level audit trail for compliance and security incident investigation.

### Why NLB Access Logs Are NOT Included

Network Load Balancer (NLB) access logs are **intentionally not configured** for this module because:

1. **Layer 4 Passthrough**: NLB operates at Layer 4 (TCP/UDP) and cannot see into the TLS tunnel between OpenVPN client and server
2. **No Application Visibility**: NLB only sees "TCP connection from IP X to port 1194" - no user identity, no authentication events
3. **Redundant Data**: VPC Flow Logs already capture this network metadata
4. **Compliance Gap**: ISO 27001 requires user access logs, which NLB cannot provide

**Bottom line:** For OpenVPN, NLB logs provide no additional value over VPC Flow Logs.

### Querying Logs for Compliance

Use CloudWatch Logs Insights to query OpenVPN logs:

```
# Find all connections from a specific user
fields @timestamp, @message
| filter @message like /user@example.com/
| sort @timestamp desc

# Find all authentication failures
fields @timestamp, @message
| filter @message like /AUTH.*FAILED/
| sort @timestamp desc

# Calculate connection duration for a user
fields @timestamp, @message
| filter @message like /CONNECTED/ or @message like /DISCONNECTED/
| stats count() by bin(5m)
```

### Log Retention and Costs

- **Default retention**: 365 days (1 year)
- **Configurable via**: `cloudwatch_log_retention_days` variable
- **Valid values**: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653, or 0 (never expire)
- **Cost optimization**: Set to 90 days for cost savings if long-term retention not required

### Compliance Recommendations

For **ISO 27001** or other compliance frameworks:

1. ✅ **Enable VPC Flow Logs** (if not already enabled)
2. ✅ **Configure log retention** according to your compliance requirements (365 days default)
3. ✅ **Set up CloudWatch alarms** for authentication failures
4. ✅ **Regular log reviews** using CloudWatch Logs Insights
5. ✅ **Export to S3** for long-term archival (if retention > 3653 days required)

<!-- BEGIN_TF_DOCS -->

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.5 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.11, < 7.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | ~> 4.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.25.0 |
| <a name="provider_aws.dns"></a> [aws.dns](#provider\_aws.dns) | 6.25.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.7.2 |
| <a name="provider_tls"></a> [tls](#provider\_tls) | 4.1.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_ca_passkey"></a> [ca\_passkey](#module\_ca\_passkey) | registry.infrahouse.com/infrahouse/secret/aws | 1.1.0 |
| <a name="module_flask_secret_key"></a> [flask\_secret\_key](#module\_flask\_secret\_key) | registry.infrahouse.com/infrahouse/secret/aws | 1.1.0 |
| <a name="module_google_client"></a> [google\_client](#module\_google\_client) | registry.infrahouse.com/infrahouse/secret/aws | 1.1.0 |
| <a name="module_instance_profile"></a> [instance\_profile](#module\_instance\_profile) | registry.infrahouse.com/infrahouse/instance-profile/aws | 1.9.0 |
| <a name="module_openvpn-portal"></a> [openvpn-portal](#module\_openvpn-portal) | registry.infrahouse.com/infrahouse/ecs/aws | 7.0.0 |
| <a name="module_userdata"></a> [userdata](#module\_userdata) | registry.infrahouse.com/infrahouse/cloud-init/aws | 2.2.2 |

## Resources

| Name | Type |
|------|------|
| [aws_autoscaling_group.openvpn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group) | resource |
| [aws_cloudwatch_log_group.openvpn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_metric_alarm.cpu_utilization_alarm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_efs_file_system.openvpn-config-enc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_file_system) | resource |
| [aws_efs_mount_target.openvpn-config-enc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_mount_target) | resource |
| [aws_iam_policy.openvpn_portal_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.openvpn_portal_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.task_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_key_pair.deployer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/key_pair) | resource |
| [aws_launch_template.openvpn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_lb.openvpn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.openvpn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_target_group.openvpn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_route53_record.vpn_cname](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_security_group.efs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.openvpn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.efs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.efs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.efs_icmp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.icmp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.openvpn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.ssh](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [random_password.ca_passkey](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.flask_secret_key](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_string.asg_name](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [random_string.profile-suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [random_string.role-suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [tls_private_key.rsa](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [aws_ami.selected](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |
| [aws_ami.ubuntu_pro](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_default_tags.provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/default_tags) | data source |
| [aws_iam_policy_document.instance_permissions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.openvpn_portal_role_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.openvpn_portal_role_permissions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_internet_gateway.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/internet_gateway) | data source |
| [aws_kms_key.efs_default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/kms_key) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_route53_zone.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/route53_zone) | data source |
| [aws_subnet.selected](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnet) | data source |
| [aws_vpc.selected](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_alarm_emails"></a> [alarm\_emails](#input\_alarm\_emails) | List of email addresses to receive CloudWatch alarm notifications for the OpenVPN portal ECS service. | `list(string)` | n/a | yes |
| <a name="input_alb_access_log_force_destroy"></a> [alb\_access\_log\_force\_destroy](#input\_alb\_access\_log\_force\_destroy) | Destroy S3 bucket with access logs even if non-empty | `bool` | `false` | no |
| <a name="input_allowed_domains"></a> [allowed\_domains](#input\_allowed\_domains) | List of domains, authenticated users of which will be allowed to connect to VPN. The domain passed via var.zone\_id will be added to the list | `list(string)` | `[]` | no |
| <a name="input_asg_ami"></a> [asg\_ami](#input\_asg\_ami) | Image for EC2 instances | `string` | `null` | no |
| <a name="input_asg_health_check_grace_period"></a> [asg\_health\_check\_grace\_period](#input\_asg\_health\_check\_grace\_period) | ASG will wait up to this number of minutes for instance to become healthy | `number` | `600` | no |
| <a name="input_asg_max_size"></a> [asg\_max\_size](#input\_asg\_max\_size) | Maximum number of instances in ASG | `number` | `null` | no |
| <a name="input_asg_min_size"></a> [asg\_min\_size](#input\_asg\_min\_size) | Minimum number of instances in ASG | `number` | `null` | no |
| <a name="input_backend_subnet_ids"></a> [backend\_subnet\_ids](#input\_backend\_subnet\_ids) | List of subnet ids where the webserver and database instances will be created | `list(string)` | n/a | yes |
| <a name="input_cloudinit_extra_commands"></a> [cloudinit\_extra\_commands](#input\_cloudinit\_extra\_commands) | Extra commands for run on ASG. | `list(string)` | `[]` | no |
| <a name="input_cloudwatch_log_retention_days"></a> [cloudwatch\_log\_retention\_days](#input\_cloudwatch\_log\_retention\_days) | Number of days to retain CloudWatch Logs for all services (NLB access logs, ECS logs, etc.) | `number` | `365` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Name of environment. | `string` | `"development"` | no |
| <a name="input_extra_files"></a> [extra\_files](#input\_extra\_files) | Additional files to create on an instance. | <pre>list(<br/>    object(<br/>      {<br/>        content     = string<br/>        path        = string<br/>        permissions = string<br/>      }<br/>    )<br/>  )</pre> | `[]` | no |
| <a name="input_extra_instance_profile_permissions"></a> [extra\_instance\_profile\_permissions](#input\_extra\_instance\_profile\_permissions) | A JSON with a permissions policy document. The policy will be attached to the ASG instance profile. | `string` | `null` | no |
| <a name="input_extra_policies"></a> [extra\_policies](#input\_extra\_policies) | A map of additional policy ARNs to attach to the jumphost role | `map(string)` | `{}` | no |
| <a name="input_extra_repos"></a> [extra\_repos](#input\_extra\_repos) | Additional APT repositories to configure on an instance. | <pre>map(<br/>    object(<br/>      {<br/>        source   = string<br/>        key      = string<br/>        machine  = optional(string)<br/>        authFrom = optional(string)<br/>        priority = optional(number)<br/>      }<br/>    )<br/>  )</pre> | `{}` | no |
| <a name="input_google_oauth_client_writer"></a> [google\_oauth\_client\_writer](#input\_google\_oauth\_client\_writer) | ARN of an IAM role that can update content of google\_oauth\_client secret | `string` | n/a | yes |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | Instance type to run the OpenVPN instances | `string` | `"m6in.large"` | no |
| <a name="input_key_pair_name"></a> [key\_pair\_name](#input\_key\_pair\_name) | SSH keypair name to be deployed in EC2 instances | `string` | `null` | no |
| <a name="input_lb_subnet_ids"></a> [lb\_subnet\_ids](#input\_lb\_subnet\_ids) | List of subnet ids where the load balancer will be created | `list(string)` | n/a | yes |
| <a name="input_on_demand_base_capacity"></a> [on\_demand\_base\_capacity](#input\_on\_demand\_base\_capacity) | If specified, the ASG will request spot instances and this will be the minimal number of on-demand instances. | `number` | `null` | no |
| <a name="input_packages"></a> [packages](#input\_packages) | List of packages to install when the instances bootstraps. | `list(string)` | `[]` | no |
| <a name="input_portal-image"></a> [portal-image](#input\_portal-image) | OpenVPN portal docker image | `string` | `"public.ecr.aws/infrahouse/openvpn-portal:latest"` | no |
| <a name="input_portal_instance_type"></a> [portal\_instance\_type](#input\_portal\_instance\_type) | AWS instance type for the portal service | `string` | `"t3.small"` | no |
| <a name="input_portal_workers_count"></a> [portal\_workers\_count](#input\_portal\_workers\_count) | Number of unicorn workers in OpenVPN portal | `number` | `4` | no |
| <a name="input_puppet_custom_facts"></a> [puppet\_custom\_facts](#input\_puppet\_custom\_facts) | A map of custom puppet facts | `any` | `{}` | no |
| <a name="input_puppet_debug_logging"></a> [puppet\_debug\_logging](#input\_puppet\_debug\_logging) | Enable debug logging if true. | `bool` | `false` | no |
| <a name="input_puppet_environmentpath"></a> [puppet\_environmentpath](#input\_puppet\_environmentpath) | A path for directory environments. | `string` | `"{root_directory}/environments"` | no |
| <a name="input_puppet_hiera_config_path"></a> [puppet\_hiera\_config\_path](#input\_puppet\_hiera\_config\_path) | Path to hiera configuration file. | `string` | `"{root_directory}/environments/{environment}/hiera.yaml"` | no |
| <a name="input_puppet_manifest"></a> [puppet\_manifest](#input\_puppet\_manifest) | Path to puppet manifest. By default ih-puppet will apply {root\_directory}/environments/{environment}/manifests/site.pp. | `string` | `null` | no |
| <a name="input_puppet_module_path"></a> [puppet\_module\_path](#input\_puppet\_module\_path) | Path to common puppet modules. | `string` | `"{root_directory}/environments/{environment}/modules:{root_directory}/modules"` | no |
| <a name="input_puppet_root_directory"></a> [puppet\_root\_directory](#input\_puppet\_root\_directory) | Path where the puppet code is hosted. | `string` | `"/opt/puppet-code"` | no |
| <a name="input_root_volume_size"></a> [root\_volume\_size](#input\_root\_volume\_size) | Root volume size in EC2 instance in Gigabytes | `number` | `30` | no |
| <a name="input_routes"></a> [routes](#input\_routes) | List of network/netmasks in format 10.x.x.x/255.x.x.x that need to be pushed to a client. [{network: "10.0.0.0", netmask: "255.0.0.0"}] | <pre>list(<br/>    object(<br/>      {<br/>        network : string,<br/>        netmask : string<br/>      }<br/>    )<br/>  )</pre> | `[]` | no |
| <a name="input_service_name"></a> [service\_name](#input\_service\_name) | DNS hostname for the service. It's also used to name some resources like EC2 instances. | `string` | `"openvpn"` | no |
| <a name="input_smtp_credentials_secret"></a> [smtp\_credentials\_secret](#input\_smtp\_credentials\_secret) | AWS secret name with SMTP credentials. The secret must contain a JSON with user and password keys. | `string` | `null` | no |
| <a name="input_sns_topic_alarm_arn"></a> [sns\_topic\_alarm\_arn](#input\_sns\_topic\_alarm\_arn) | ARN of SNS topic for Cloudwatch alarms on base EC2 instance. | `string` | `null` | no |
| <a name="input_ubuntu_codename"></a> [ubuntu\_codename](#input\_ubuntu\_codename) | Ubuntu version to use for the OpenVPN server EC2 instance | `string` | `"noble"` | no |
| <a name="input_users"></a> [users](#input\_users) | A list of maps with user definitions according to the cloud-init format | `any` | `null` | no |
| <a name="input_zone_id"></a> [zone\_id](#input\_zone\_id) | Domain name zone ID where the website will be available | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_autoscaling_group_name"></a> [autoscaling\_group\_name](#output\_autoscaling\_group\_name) | Name of the autoscaling group managing the OpenVPN instances |
| <a name="output_google_client_secret"></a> [google\_client\_secret](#output\_google\_client\_secret) | Google OAuth client secret name. The OpenVPN portal admin must update the secret with a Google OAuth client JSON. |
| <a name="output_load_balancer_arn"></a> [load\_balancer\_arn](#output\_load\_balancer\_arn) | ARN of the load balancer for the OpenVPN portal |
| <a name="output_openvpn-instance-role-arn"></a> [openvpn-instance-role-arn](#output\_openvpn-instance-role-arn) | ARN of the IAM role attached to the OpenVPN instance |
| <a name="output_portal_url"></a> [portal\_url](#output\_portal\_url) | URL of the OpenVPN portal web interface |
<!-- END_TF_DOCS -->
