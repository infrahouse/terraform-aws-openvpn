# Architecture

The module assembles several AWS components into a self-service VPN with Google authentication.

## Overview

```mermaid
flowchart TB
    user([User])

    subgraph public[Public subnets]
        nlb[Network Load Balancer<br/>UDP/TCP 1194]
        alb[Portal ALB<br/>HTTPS 443]
    end

    subgraph private[Private subnets]
        asg[OpenVPN ASG<br/>EC2 instances]
        portal[OpenVPN Portal<br/>ECS service]
        efs[(EFS<br/>encrypted config)]
    end

    secrets[[Secrets Manager<br/>CA passkey · Flask key · Google OAuth]]
    r53[Route 53]
    cw[CloudWatch<br/>logs · metrics · alarms]

    user -->|VPN tunnel| nlb --> asg
    user -->|browser| alb --> portal
    portal -->|reads CA / writes profiles| efs
    asg -->|reads CA / config| efs
    portal --> secrets
    asg --> secrets
    asg --> cw
    r53 -.->|DNS| nlb
    r53 -.->|DNS| alb
```

## Components

### OpenVPN server (Auto Scaling group)

- Ubuntu EC2 instances (default `c6in.large`, compute-optimized for encryption workloads) in the
  **private** backend subnets.
- Managed by an Auto Scaling group with target-tracking policies on **CPU** and **network
  bandwidth**, so the fleet scales when either dimension saturates.
- A 10-minute (600s) health-check grace period lets new instances mount EFS and initialize OpenVPN
  before health checks apply.
- Bootstrapped via cloud-init (`infrahouse/cloud-init/aws`); configuration is rendered into Puppet.

### Network Load Balancer

- Sits in the **public** subnets and forwards OpenVPN traffic on port `1194` to the ASG target
  group.
- Provides a stable DNS endpoint (`vpn_server_fqdn`) for clients via a Route 53 CNAME.

### OpenVPN Portal (ECS service)

- A Flask application (`public.ecr.aws/infrahouse/openvpn-portal`) run as an ECS service through the
  `infrahouse/ecs/aws` module, fronted by its own **Application Load Balancer** on HTTPS.
- Handles **Google OAuth** sign-in, validates the user's domain, and serves a per-user `.ovpn`
  profile.
- The ALB **access-log bucket** is replicated to `replication_region` for audit/DR compliance.

### EFS (shared configuration)

- An **encrypted** EFS file system stores the OpenVPN CA, certificates, and server config.
- Mounted by both the OpenVPN instances and the portal tasks, so any instance can serve any user
  and config survives instance replacement.
- Protected by **AWS Backup** (enabled by default, 365-day retention).

### Secrets

All secrets use the `infrahouse/secret/aws` module:

- **CA passkey** — randomly generated, protects the OpenVPN certificate authority.
- **Flask secret key** — signs portal session cookies.
- **Google OAuth client** — placeholder you populate after the first deploy.

### Observability

- OpenVPN server logs ship to a **CloudWatch Log Group** (365-day retention by default).
- A **CPU utilization alarm** notifies `alarm_emails` (and an optional SNS topic).
- Portal logs flow to CloudWatch through the ECS module.

## Network flow

1. A user opens the portal URL; Route 53 resolves it to the portal ALB.
2. The portal authenticates the user against Google and checks their domain against
   `allowed_domains`.
3. The portal generates a profile from the CA on EFS and serves it.
4. The client connects to the NLB on `1194`; the NLB forwards to a healthy OpenVPN instance.
5. The instance pushes the configured `routes` so the client can reach private resources.

## Multi-domain support

From version 4.0.0, the portal accepts users from multiple Google Workspace domains. The domain
derived from `zone_id` is always allowed; additional domains are listed in `allowed_domains`. Using
more than one domain requires marking the Google OAuth app **External**.
