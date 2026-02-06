variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "lambda_function_name" {
  description = "Nombre de la función Lambda"
  type        = string
  default     = "rds-aurora-backup-automation"
}

variable "backup_vault_name" {
  description = "Nombre del Backup Vault"
  type        = string
  default     = "Default"
}

variable "use_existing_vault" {
  description = "Si es true, usa un vault existente. Si es false, crea uno nuevo."
  type        = bool
  default     = true  # Por defecto intenta usar el existente
}

variable "retention_days" {
  description = "Días de retención de backups"
  type        = number
  default     = 5
}

variable "backup_schedule" {
  description = "Expresión cron para ejecutar backups (UTC)"
  type        = string
  default     = "cron(0 2 * * ? *)" # Diario a las 2 AM UTC
}

variable "backup_tag_key" {
  description = "Tag key para identificar recursos a respaldar"
  type        = string
  default     = "Backup"
}

variable "backup_tag_value" {
  description = "Tag value para identificar recursos a respaldar"
  type        = string
  default     = "True"
}

variable "tags" {
  description = "Tags comunes para todos los recursos"
  type        = map(string)
  default = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Project     = "RDS-Backup-Automation"
  }
}