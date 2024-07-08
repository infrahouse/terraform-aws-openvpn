The [openvpn module](https://registry.terraform.io/modules/infrahouse/openvpn/aws/latest) deploys an OpenVPN server 
with Google OAuth2.0 authentication.

![OpenVPN diagram](https://raw.githubusercontent.com/infrahouse/terraform-aws-openvpn/main/assets/openvpn.drawio.png)

OpenVPN Portal is a web application. It authenticates users by their Google account and generates 
an OpenVPN profile for them.

You would put the OpenVPN server in a public subnet in your AWS cloud to give access to authorized users 
to AWS resources in private subnets.

## Installation

To illustrate how to use the module, I will deploy a VPN server for InfraHouse.

### **Step 1**: Create a Terraform code.
```hcl
module "vpn" {
  source  = "registry.infrahouse.com/infrahouse/openvpn/aws"
  version = "~> 0.2"
  providers = {
    aws     = aws
    aws.dns = aws
  }
  backend_subnet_ids         = module.management.subnet_private_ids
  lb_subnet_ids              = module.management.subnet_public_ids
  google_oauth_client_writer = data.aws_iam_role.AWSAdministratorAccess.arn
  zone_id                    = module.infrahouse_com.infrahouse_zone_id
}

data "aws_iam_role" "AWSAdministratorAccess" {
  name = "AWSReservedSSO_AWSAdministratorAccess_a84a03e62f490b50"
}
```
Our VPN setup will consist of two components: OpenVPN server and OpenVPN Portal

The OpenVPN server is deployed on an autoscale group and fronted by a network load balancer.

![openvp-server](https://raw.githubusercontent.com/infrahouse/terraform-aws-openvpn/main/assets/openvp-server.drawio.png)

The OpenVPN Portal is a Web application deployed as an AWS ECS service. 
It talks to Google to authenticate users and distributes OpenVPN profiles needed to configure a client application. 

![openvp-portal](https://raw.githubusercontent.com/infrahouse/terraform-aws-openvpn/main/assets/openvp-portal.drawio.png)

All module variables here are required. Let's go over them.

* `backend_subnet_ids`. This is a list of subnet-id-s where autoscale EC2 instances will be places. 
Access to VPN is provided by a network load balancer, so we want the EC2 instances to run in private subnets.
* `lb_subnet_ids`. This is a list of subnet-id-s where the network load balancer will be running. We want it to be in  
public subnets because it is going to be a publicly accessible gateway to our private AWS resources.  
* `google_oauth_client_writer`. The OpenVPN Portal will need credentials to talk to Google, so it can authenticate users.
`google_oauth_client_writer` is an identity ARN that has a permission to update a secret with those credentials.
More on that below. In this case, I will update the secret, so the value is a role ARN I get on my laptop 
via AWS Control Tower SSO. 
* `zone_id`. The module will create two public DNS names: openvpn.infrahouse.com and openvpn-portal.infrahouse.com.
infrahouse.com is hosted in Route53 so `zone_id` is its zone identifier.
* `providers` block. In some cases, you want the VPN and DNS resources to be managed by different roles or 
deployed in different AWS account. That's why I separated two providers. 
`aws.dns` is responsible for creating Route53 resources and the default `aws` provider does the rest. In my case, 
the VPN and infrahouse.com live in the same AWS account. so the providers are the same.   

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
+  version = "~> 0.2"
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
and we can review what Terraform is going to do.

![terraform-plan.png](https://raw.githubusercontent.com/infrahouse/terraform-aws-openvpn/main/assets/terraform-plan.png)

Normally, the module will create about 80 resources. In my case, all of them start with a "module.vnp", 
which is a good indicator Terraform will create resources that we expect it to do.
If your plan includes resources to be changed or destroyed - double-check the STDOUT to understand what's going on.

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

Now if you open https://openvpn-portal.infrahouse.com/ in a browser, you'll see a 502 error.
It's because I didn't update Google Client credentials. So, let's remedy that.

![502.png](https://raw.githubusercontent.com/infrahouse/terraform-aws-openvpn/main/assets/502.png)

This is a Google client secret that Terraform created.
```shell
$ ih-secrets --aws-region us-west-1 --aws-profile AWSAdministratorAccess-493370826424 list | grep google
| google_client20240705183915856300000015              | A JSON with Google OAuth Client ID                                                                                        |
```
If you get its value, it will show `NoValue`:
```shell
$ ih-secrets --aws-region us-west-1 --aws-profile AWSAdministratorAccess-493370826424 get google_client20240705183915856300000015
NoValue
```
#### **Step 4.1**: Create OAuth 2.0 credentials.

Open [Google Cloud Console](https://console.cloud.google.com/) and create an OpenVPN project.

![gc-1.png](https://raw.githubusercontent.com/infrahouse/terraform-aws-openvpn/main/assets/gc-1.png)

Next, go to "Credentials". 

![gc-2.png](https://raw.githubusercontent.com/infrahouse/terraform-aws-openvpn/main/assets/gc-2.png)

Next, Create OAuth client ID. Note, authentication requests will come from https://openvpn-portal.infrahouse.com,
so I added it to "Authorized JavaScript origins". Another important setting is "Authorized redirect URIs".
It must be https://openvpn-portal.infrahouse.com/login/google/authorized. For your domain it will be something like
https://openvpn-portal.my-domain.com/login/google/authorized.

![img.png](https://raw.githubusercontent.com/infrahouse/terraform-aws-openvpn/main/assets/gc-3.png)

#### **Step 4.2**: Download OAuth 2.0 credentials.

After you press a create button, you'll see a confirmation screen with a DOWNLOAD JSON link. 
Click it and save the file.

![img.png](https://raw.githubusercontent.com/infrahouse/terraform-aws-openvpn/main/assets/gc-04.png)

#### **Step 4.3**: Update Google OAuth Client ID secret value.

From a previous I know the secret name is `google_client20240705183915856300000015`. Let's update it 
with a valid value.

As a reference, the value should look like this
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

### **Step 5**: Check on OpenVPN Portal.
After a short time, the portal should pick up the new and value Google Client ID value. 
When you open https://openvpn-portal.infrahouse.com/ again, it will present a Google login window. 

After a successful authentication, the portal will show a page with OpenVPN client instructions.


![img.png](https://raw.githubusercontent.com/infrahouse/terraform-aws-openvpn/main/assets/portal-start-page.png)

### **Step 6**: Install OpenVPN client.

The portal has links to an installer for MacOS and Windows. For other OS-es you can go to https://openvpn.net/client/
and download the client from there.

![img.png](https://raw.githubusercontent.com/infrahouse/terraform-aws-openvpn/main/assets/openvpn-download-page.png)

### **Step 6**: Download and import OpenVPN profile.

Once the client is installed, click on https://openvpn-portal.infrahouse.com/profile and save the OpenVPN profile 
on your laptop.

Double-click on the `aleks@infrahouse.com-openvpn.infrahouse.com.ovpn` file. It will open the client and suggest 
to import the profile.

![img.png](https://raw.githubusercontent.com/infrahouse/terraform-aws-openvpn/main/assets/import-profile-page.png)

### **Step 7**: Connect to VPN.

| Original Image                            |    | Transformed Image                            |
|-------------------------------------------|----|----------------------------------------------|
| ![img.png](https://raw.githubusercontent.com/infrahouse/terraform-aws-openvpn/main/assets/connect-page.png)       | ➡️ | ![img.png](connected-page.png)               |


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

It's because we didn't let the VPN client what networks are accessible via the VPN tunnel.


### **Step 9**: Add routes to the VPN client.

I want to make the management VPN in the InfraHouse cloud to be available to the VPN clients. To do that, let's 
amend the module configuration.

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

When the Terraform change is applied, the OpenVPN autoscaling group triggers in instance refresh. 
It takes at least 5 to 10 minutes to rotate the instances. The openVPN client will reconnect when the server changes.
Wait until it happens and check if you can ping private IP addresses of instances in your VPC.

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