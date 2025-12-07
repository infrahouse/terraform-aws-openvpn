# Task: Add CloudWatch Logs Agent Support to Puppet OpenVPN Server Role

## Context

The `terraform-aws-openvpn` module has been updated to configure CloudWatch Logs Agent via cloud-init. 
The agent package and configuration file are deployed by Terraform, 
but **Puppet needs to manage the agent service** to ensure it starts and runs correctly.

### What Terraform Does (Already Implemented)

1. **Installs package** via cloud-init user-data:
   ```yaml
   packages:
     - amazon-cloudwatch-agent
   ```

2. **Deploys configuration file** at `/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json`:
   ```json
   {
     "logs": {
       "logs_collected": {
         "files": {
           "collect_list": [
             {
               "file_path": "/var/log/openvpn/openvpn.log",
               "log_group_name": "/aws/openvpn/development/openvpn",
               "log_stream_name": "{instance_id}/openvpn.log"
             },
             {
               "file_path": "/var/log/openvpn/openvpn-status.log",
               "log_group_name": "/aws/openvpn/development/openvpn",
               "log_stream_name": "{instance_id}/openvpn-status.log"
             },
             {
               "file_path": "/var/log/auth.log",
               "log_group_name": "/aws/openvpn/development/openvpn",
               "log_stream_name": "{instance_id}/auth.log"
             }
           ]
         }
       }
     }
   }
   ```

3. **Provides Puppet custom facts**:
   ```yaml
   custom_facts:
     openvpn:
       cloudwatch_log_group: "/aws/openvpn/development/openvpn"
   ```

## What Puppet Needs to Do

Puppet should manage the CloudWatch agent **service lifecycle**:

1. ✅ **Verify package is installed** (already done by cloud-init, but Puppet should ensure it)
2. ✅ **Start the CloudWatch agent service** using the configuration file deployed by Terraform
3. ✅ **Enable the service** to start on boot
4. ✅ **Monitor service status** and restart if it crashes

## Implementation Requirements

### File Location

Modify the OpenVPN server Puppet manifest:
- **Repository**: `puppet-code` (https://github.com/infrahouse/puppet-code)
- **File**: `modules/profile/manifests/openvpn_server.pp` (or wherever the openvpn_server role is defined)

### Puppet Code to Add

The Puppet manifest should include logic similar to this:

```puppet
# CloudWatch Logs Agent management for OpenVPN server
# The agent package and configuration are deployed by Terraform via cloud-init
# Puppet manages the service lifecycle

# Ensure the package is installed (redundant check, cloud-init should have done this)
package { 'amazon-cloudwatch-agent':
  ensure => installed,
}

# Only manage the service if the cloudwatch_log_group fact is present
# This fact is provided by Terraform in custom_facts
if $facts['openvpn'] and $facts['openvpn']['cloudwatch_log_group'] {

  # Start and enable the CloudWatch Logs Agent service
  # The configuration file is already deployed by Terraform at:
  # /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

  exec { 'start-cloudwatch-agent':
    command => '/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json',
    unless  => '/bin/systemctl is-active amazon-cloudwatch-agent',
    require => Package['amazon-cloudwatch-agent'],
  }

  # Ensure the service stays running
  service { 'amazon-cloudwatch-agent':
    ensure  => running,
    enable  => true,
    require => Exec['start-cloudwatch-agent'],
  }

  # Optionally: log the CloudWatch log group name for debugging
  notify { "CloudWatch Logs enabled for log group: ${facts['openvpn']['cloudwatch_log_group']}":
    require => Service['amazon-cloudwatch-agent'],
  }
}
```

### Alternative: Using systemd Service Directly

If you prefer to use systemd service management directly (cleaner approach):

```puppet
# CloudWatch Logs Agent management for OpenVPN server

if $facts['openvpn'] and $facts['openvpn']['cloudwatch_log_group'] {

  # Ensure package is installed
  package { 'amazon-cloudwatch-agent':
    ensure => installed,
  }

  # Ensure the CloudWatch agent is configured and started
  # Configuration file already exists from cloud-init
  exec { 'configure-cloudwatch-agent':
    command => '/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json',
    creates => '/opt/aws/amazon-cloudwatch-agent/etc/config.json',
    require => Package['amazon-cloudwatch-agent'],
    notify  => Service['amazon-cloudwatch-agent'],
  }

  # Manage the systemd service
  service { 'amazon-cloudwatch-agent':
    ensure  => running,
    enable  => true,
    require => Exec['configure-cloudwatch-agent'],
  }
}
```

### Key Points

1. **Conditional execution**: Only manage CloudWatch agent if `$facts['openvpn']['cloudwatch_log_group']` exists
   - This fact is provided by Terraform
   - If the fact is missing, Terraform didn't configure logging, so Puppet should skip it

2. **Package management**: Ensure `amazon-cloudwatch-agent` package is installed
   - Cloud-init should have already installed it
   - Puppet ensures it stays installed

3. **Service configuration**: Use `amazon-cloudwatch-agent-ctl` to load configuration
   - Configuration file path: `/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json`
   - This file is deployed by Terraform via cloud-init `extra_files`
   - Command: `-a fetch-config -m ec2 -s -c file:/path/to/config.json`

4. **Service management**: Ensure the service is running and enabled
   - Service name: `amazon-cloudwatch-agent`
   - Should start on boot
   - Should restart if it crashes

## Testing

After implementing the Puppet changes, verify:

1. **Service is running**:
   ```bash
   sudo systemctl status amazon-cloudwatch-agent
   ```

2. **Configuration is loaded**:
   ```bash
   sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a query -m ec2 -c default
   ```

3. **Logs are being shipped**:
   ```bash
   # Check CloudWatch agent logs
   sudo tail -f /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log
   ```

4. **Logs appear in CloudWatch**:
   - Use AWS Console or CLI to verify logs appear in CloudWatch Logs
   - Log group: `/aws/openvpn/{environment}/{service_name}`
   - Log streams: `{instance_id}/openvpn.log`, `{instance_id}/openvpn-status.log`, `{instance_id}/auth.log`

## Integration with terraform-aws-openvpn

The Terraform module provides these inputs to Puppet via custom facts:

```hcl
custom_facts = {
  openvpn = {
    cloudwatch_log_group = aws_cloudwatch_log_group.openvpn.name
    # Example: "/aws/openvpn/development/openvpn"
  }
}
```

Puppet can access this via: `$facts['openvpn']['cloudwatch_log_group']`

## Files to Modify

1. **Main file**: `modules/profile/manifests/openvpn_server.pp`
   - Add CloudWatch agent service management logic

2. **Optional**: Create a separate class if you want to reuse CloudWatch agent management:
   - `modules/profile/manifests/cloudwatch_agent.pp`
   - Include it in `openvpn_server.pp` with: `include profile::cloudwatch_agent`

## References

- **CloudWatch Agent Documentation**: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/install-CloudWatch-Agent-on-EC2-Instance.html
- **Agent Control Script**: `/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl`
- **Terraform Module**: `terraform-aws-openvpn` (already implemented)
- **Test File**: `terraform-aws-openvpn/tests/test_module.py::test_cloudwatch_logging()`

## Success Criteria

✅ CloudWatch agent service starts automatically after Puppet run
✅ Service is enabled to start on boot
✅ Logs from `/var/log/openvpn/*.log` and `/var/log/auth.log` appear in CloudWatch
✅ `terraform-aws-openvpn` pytest tests pass (specifically `test_cloudwatch_logging()`)
✅ Puppet runs are idempotent (no changes on subsequent runs if service is already running)

## Questions?

If you need clarification on any part of this implementation, please ask!
