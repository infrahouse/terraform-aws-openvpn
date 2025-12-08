# IAM policy document for AWS Backup service assume role
data "aws_iam_policy_document" "backup_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# AWS Backup vault for EFS backups
resource "aws_backup_vault" "efs" {
  count = var.enable_efs_backup ? 1 : 0
  name  = "${var.service_name}-efs-backup-vault"

  tags = merge(
    {
      Name = "${var.service_name}-efs-backup-vault"
    },
    local.default_module_tags
  )
}

# AWS Backup plan for daily EFS backups
resource "aws_backup_plan" "efs" {
  count = var.enable_efs_backup ? 1 : 0
  name  = "${var.service_name}-efs-backup-plan"

  rule {
    rule_name         = "${var.service_name}-efs-daily-backup"
    target_vault_name = aws_backup_vault.efs[0].name
    schedule          = var.efs_backup_schedule

    lifecycle {
      delete_after = var.efs_backup_retention_days
    }

    # Enable continuous backup for point-in-time restore
    enable_continuous_backup = false
  }

  tags = merge(
    {
      Name = "${var.service_name}-efs-backup-plan"
    },
    local.default_module_tags
  )
}

# IAM role for AWS Backup service
resource "aws_iam_role" "backup" {
  count              = var.enable_efs_backup ? 1 : 0
  name               = "${var.service_name}-efs-backup-role-${random_string.role-suffix.result}"
  assume_role_policy = data.aws_iam_policy_document.backup_assume_role.json

  tags = merge(
    {
      Name = "${var.service_name}-efs-backup-role"
    },
    local.default_module_tags
  )
}

# Attach AWS managed backup policy for EFS
resource "aws_iam_role_policy_attachment" "backup_efs" {
  count      = var.enable_efs_backup ? 1 : 0
  role       = aws_iam_role.backup[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

# Attach AWS managed restore policy for EFS
resource "aws_iam_role_policy_attachment" "backup_restore" {
  count      = var.enable_efs_backup ? 1 : 0
  role       = aws_iam_role.backup[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# AWS Backup selection - specify which resources to back up
resource "aws_backup_selection" "efs" {
  count        = var.enable_efs_backup ? 1 : 0
  name         = "${var.service_name}-efs-backup-selection"
  iam_role_arn = aws_iam_role.backup[0].arn
  plan_id      = aws_backup_plan.efs[0].id

  resources = [
    aws_efs_file_system.openvpn-config-enc.arn
  ]
}