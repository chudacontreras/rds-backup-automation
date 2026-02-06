output "lambda_function_name" {
  description = "Nombre de la función Lambda"
  value       = aws_lambda_function.backup_lambda.function_name
}

output "lambda_function_arn" {
  description = "ARN de la función Lambda"
  value       = aws_lambda_function.backup_lambda.arn
}

output "backup_role_arn" {
  description = "ARN del rol de AWS Backup"
  value       = aws_iam_role.backup_role.arn
}

output "backup_vault_name" {
  description = "Nombre del Backup Vault utilizado"
  value       = local.backup_vault_name
}

output "backup_vault_arn" {
  description = "ARN del Backup Vault"
  value       = local.backup_vault_arn
}

output "vault_source" {
  description = "Indica si el vault es existente o nuevo"
  value       = var.use_existing_vault ? "existing" : "newly_created"
}

output "cloudwatch_log_group" {
  description = "CloudWatch Log Group de Lambda"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "sns_topic_arn" {
  description = "ARN del SNS Topic para notificaciones"
  value       = aws_sns_topic.backup_notifications.arn
}

output "backup_schedule" {
  description = "Expresión cron del schedule de backups"
  value       = var.backup_schedule
}

output "eventbridge_rule_name" {
  description = "Nombre de la regla de EventBridge"
  value       = aws_cloudwatch_event_rule.backup_schedule.name
}

output "kms_key_id" {
  description = "ID de la KMS key (solo si se creó nuevo vault)"
  value       = var.use_existing_vault ? "N/A - Using existing vault" : aws_kms_key.backup_vault_key[0].key_id
}