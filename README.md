# RDS y Aurora Backup Automation con Terraform

## 📋 Descripción
Solución completa de automatización de backups para instancias RDS y clusters Aurora usando AWS Backup, Lambda y EventBridge. Implementado con Terraform para infraestructura como código.

## 🎯 Características

### ✅ Funcionalidades Principales
- **Backup Automático**: Backups programados de RDS y Aurora basados en tags
- **Gestión Flexible de Vault**: Usa vault existente o crea uno nuevo con KMS
- **Retención Configurable**: Política de retención personalizable por días
- **Monitoreo Integrado**: CloudWatch Logs, Alarms y SNS notifications
- **Idempotencia**: Previene backups duplicados con tokens únicos
- **Logging Detallado**: Logs estructurados con emojis para fácil lectura
- **Manejo de Errores**: Reintentos automáticos y reportes de fallos

### 🏗️ Componentes Desplegados
- **Lambda Function**: Función Python 3.11 para orquestar backups
- **AWS Backup Vault**: Almacenamiento seguro de recovery points
- **KMS Key**: Cifrado de backups (opcional, solo para vault nuevo)
- **IAM Roles**: Permisos mínimos necesarios para Lambda y Backup
- **EventBridge Rule**: Programación de ejecuciones automáticas
- **CloudWatch**: Logs, métricas y alarmas
- **SNS Topic**: Notificaciones de errores

## 📁 Estructura del Proyecto

```
rds-backup-automation-2/
├── main.tf                              # Configuración principal de recursos
├── variables.tf                         # Definición de variables
├── outputs.tf                           # Outputs de Terraform
├── terraform.tfvars                     # Valores de configuración
├── rds-aurora-backup-automation.py      # Código Lambda standalone (referencia)
├── lambda_payload.zip                   # Generado automáticamente
└── README.md                            # Esta documentación
```

## 🚀 Inicio Rápido

### Prerrequisitos
```bash
# Terraform >= 1.0
terraform version

# AWS CLI configurado
aws configure list

# Permisos IAM necesarios
# - Crear Lambda, IAM Roles, EventBridge, CloudWatch
# - Gestionar AWS Backup Vaults y KMS Keys
```

### Instalación

#### 1. Clonar y Configurar
```bash
cd Terraform/rds-backup-automation-2

# Editar terraform.tfvars según tus necesidades
nano terraform.tfvars
```

#### 2. Configurar Variables
```hcl
# terraform.tfvars
aws_region         = "us-east-1"
backup_vault_name  = "Default"           # Nombre del vault
use_existing_vault = true                # true = usar existente, false = crear nuevo
retention_days     = 5                   # Días de retención
backup_tag_key     = "Backup"            # Tag key para identificar recursos
backup_tag_value   = "True"              # Tag value requerido
backup_schedule    = "cron(0 2 * * ? *)" # Diario a las 2 AM UTC

tags = {
  Environment = "Production"
  ManagedBy   = "Terraform"
  Project     = "RDS-Backup-Automation"
}
```

#### 3. Desplegar Infraestructura
```bash
# Inicializar Terraform
terraform init

# Revisar plan de ejecución
terraform plan

# Aplicar cambios
terraform apply
```

## 🔧 Configuración Detallada

### Variables Principales

| Variable | Tipo | Default | Descripción |
|----------|------|---------|-------------|
| `aws_region` | string | `us-east-1` | Región de AWS |
| `lambda_function_name` | string | `rds-aurora-backup-automation-2` | Nombre de la función Lambda |
| `backup_vault_name` | string | `Default` | Nombre del Backup Vault |
| `use_existing_vault` | bool | `true` | Usar vault existente o crear nuevo |
| `retention_days` | number | `5` | Días de retención de backups |
| `backup_schedule` | string | `cron(0 2 * * ? *)` | Expresión cron para schedule |
| `backup_tag_key` | string | `Backup` | Tag key para identificar recursos |
| `backup_tag_value` | string | `True` | Tag value requerido |
| `tags` | map(string) | `{}` | Tags comunes para recursos |

### Expresiones Cron de EventBridge

```bash
# Diario a las 2 AM UTC
cron(0 2 * * ? *)

# Cada 6 horas
cron(0 */6 * * ? *)

# Lunes a Viernes a las 3 AM UTC
cron(0 3 ? * MON-FRI *)

# Primer día del mes a las 1 AM UTC
cron(0 1 1 * ? *)

# Cada domingo a las 4 AM UTC
cron(0 4 ? * SUN *)
```

## 🏷️ Etiquetado de Recursos

### Etiquetar Instancias RDS
```bash
# Via AWS CLI
aws rds add-tags-to-resource \
  --resource-name arn:aws:rds:us-east-1:123456789012:db:mi-instancia \
  --tags Key=Backup,Value=True

# Via Terraform
resource "aws_db_instance" "example" {
  # ... otras configuraciones
  
  tags = {
    Backup = "True"
  }
}
```

### Etiquetar Clusters Aurora
```bash
# Via AWS CLI
aws rds add-tags-to-resource \
  --resource-name arn:aws:rds:us-east-1:123456789012:cluster:mi-cluster \
  --tags Key=Backup,Value=True

# Via Terraform
resource "aws_rds_cluster" "example" {
  # ... otras configuraciones
  
  tags = {
    Backup = "True"
  }
}
```

## 🔐 Permisos IAM

### Permisos de Lambda
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "rds:DescribeDBInstances",
        "rds:DescribeDBClusters",
        "rds:ListTagsForResource"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "backup:StartBackupJob",
        "backup:DescribeBackupVault"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::*:role/*backup-role"
    }
  ]
}
```

### Permisos de AWS Backup
- `AWSBackupServiceRolePolicyForBackup`
- `AWSBackupServiceRolePolicyForRestores`

## 📊 Monitoreo y Logs

### CloudWatch Logs
```bash
# Ver logs en tiempo real
aws logs tail /aws/lambda/rds-aurora-backup-automation-2 --follow

# Buscar errores
aws logs filter-log-events \
  --log-group-name /aws/lambda/rds-aurora-backup-automation-2 \
  --filter-pattern "ERROR"

# Ver últimos 100 eventos
aws logs tail /aws/lambda/rds-aurora-backup-automation-2 --since 1h
```

### Formato de Logs
```
========================================================
🚀 INICIANDO BACKUP AUTOMATIZADO
📦 Vault: Default
⏰ Retención: 5 días
🏷️  Tag: Backup=True
========================================================
🔍 Buscando instancias RDS...
  ✓ RDS: mi-db-prod (postgres)
📌 Total RDS encontradas: 1
🔍 Buscando clusters Aurora...
  ✓ Aurora: mi-cluster-prod (aurora-postgresql)
📌 Total Aurora encontrados: 1
💾 Iniciando backup RDS: mi-db-prod
  ✅ Job ID: 12345678-1234-1234-1234-123456789012
💾 Iniciando backup Aurora: mi-cluster-prod
  ✅ Job ID: 87654321-4321-4321-4321-210987654321
========================================================
✅ Exitosos: 2
❌ Fallidos: 0
📊 Total procesados: 2
========================================================
```

### CloudWatch Metrics
```bash
# Ver métricas de Lambda
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=rds-aurora-backup-automation-2 \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-02T00:00:00Z \
  --period 3600 \
  --statistics Sum
```

## 🧪 Testing

### Prueba Manual
```bash
# Invocar Lambda manualmente
aws lambda invoke \
  --function-name rds-aurora-backup-automation-2 \
  --payload '{}' \
  response.json

# Ver resultado
cat response.json | jq
```

### Verificar Backups Creados
```bash
# Listar recovery points en el vault
aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name Default

# Ver detalles de un backup job
aws backup describe-backup-job \
  --backup-job-id <JOB_ID>
```

### Verificar Tags en Recursos
```bash
# RDS Instance
aws rds list-tags-for-resource \
  --resource-name arn:aws:rds:us-east-1:123456789012:db:mi-instancia

# Aurora Cluster
aws rds list-tags-for-resource \
  --resource-name arn:aws:rds:us-east-1:123456789012:cluster:mi-cluster
```

## 🔄 Casos de Uso

### Caso 1: Usar Vault Existente "Default"
```hcl
# terraform.tfvars
backup_vault_name  = "Default"
use_existing_vault = true
```

### Caso 2: Crear Vault Nuevo con KMS
```hcl
# terraform.tfvars
backup_vault_name  = "RDS-Production-Backups"
use_existing_vault = false
```

### Caso 3: Backups Solo de Producción
```hcl
# terraform.tfvars
backup_tag_key   = "Environment"
backup_tag_value = "Production"
```

### Caso 4: Retención Extendida
```hcl
# terraform.tfvars
retention_days = 30  # 30 días de retención
```

### Caso 5: Múltiples Schedules
```bash
# Crear múltiples instancias del módulo con diferentes schedules
# main.tf
module "backup_daily" {
  source = "./rds-backup-automation-2"
  backup_schedule = "cron(0 2 * * ? *)"
  backup_tag_value = "Daily"
}

module "backup_weekly" {
  source = "./rds-backup-automation-2"
  backup_schedule = "cron(0 3 ? * SUN *)"
  backup_tag_value = "Weekly"
  retention_days = 30
}
```

## 🐛 Troubleshooting

### Error: "Backup vault already exists"
```bash
# Solución 1: Usar vault existente
use_existing_vault = true

# Solución 2: Cambiar nombre del vault
backup_vault_name = "RDS-Backup-Vault-New"

# Solución 3: Limpiar estado de Terraform
terraform state rm 'aws_backup_vault.new[0]'
terraform apply
```

### Error: "No resources found with specified tags"
```bash
# Verificar tags en recursos
aws rds describe-db-instances \
  --query 'DBInstances[*].[DBInstanceIdentifier,TagList]'

# Agregar tags faltantes
aws rds add-tags-to-resource \
  --resource-name <ARN> \
  --tags Key=Backup,Value=True
```

### Error: "Access Denied" en Lambda
```bash
# Verificar permisos del rol
aws iam get-role-policy \
  --role-name rds-aurora-backup-automation-2-lambda-role \
  --policy-name rds-aurora-backup-automation-2-policy

# Verificar que el rol puede asumir Lambda
aws iam get-role \
  --role-name rds-aurora-backup-automation-2-lambda-role
```

### Backups No Se Ejecutan
```bash
# Verificar EventBridge rule
aws events describe-rule \
  --name rds-aurora-backup-automation-2-schedule

# Verificar targets
aws events list-targets-by-rule \
  --rule rds-aurora-backup-automation-2-schedule

# Verificar permisos de invocación
aws lambda get-policy \
  --function-name rds-aurora-backup-automation-2
```

### Lambda Timeout
```bash
# Aumentar timeout en variables.tf o main.tf
resource "aws_lambda_function" "backup_lambda" {
  timeout = 900  # 15 minutos (máximo)
}
```

## 📈 Optimización de Costos

### Estimación de Costos
```
Componentes:
- Lambda: $0.20 por millón de requests + $0.0000166667 por GB-segundo
- AWS Backup: $0.05 por GB-mes (almacenamiento)
- CloudWatch Logs: $0.50 por GB ingested
- EventBridge: Gratis para reglas programadas
- SNS: $0.50 por millón de notificaciones

Ejemplo (10 RDS/Aurora, backups diarios):
- Lambda: ~$0.01/mes
- Backup Storage (100 GB, 5 días): ~$0.83/mes
- CloudWatch: ~$0.10/mes
Total estimado: ~$1/mes + costos de almacenamiento
```

### Reducir Costos
```hcl
# Reducir retención
retention_days = 3

# Backups menos frecuentes
backup_schedule = "cron(0 2 ? * SUN *)"  # Solo domingos

# Reducir logs retention
resource "aws_cloudwatch_log_group" "lambda_logs" {
  retention_in_days = 7  # En lugar de 14
}
```

## 🔄 Actualización y Mantenimiento

### Actualizar Código Lambda
```bash
# Terraform detecta cambios automáticamente en el código inline
terraform plan
terraform apply
```

### Cambiar Schedule
```bash
# Editar terraform.tfvars
backup_schedule = "cron(0 3 * * ? *)"  # Cambiar a 3 AM

# Aplicar cambios
terraform apply
```

### Migrar de Vault Existente a Nuevo
```bash
# 1. Cambiar configuración
use_existing_vault = false
backup_vault_name = "RDS-Backup-Vault-New"

# 2. Aplicar
terraform apply

# 3. Copiar backups existentes (manual via AWS Console o CLI)
```

## 📚 Outputs de Terraform

Después de `terraform apply`, obtendrás:

```hcl
lambda_function_name = "rds-aurora-backup-automation-2"
lambda_function_arn = "arn:aws:lambda:us-east-1:123456789012:function:rds-aurora-backup-automation-2"
backup_vault_name = "Default"
backup_vault_arn = "arn:aws:backup:us-east-1:123456789012:backup-vault:Default"
vault_source = "existing"
cloudwatch_log_group = "/aws/lambda/rds-aurora-backup-automation-2"
sns_topic_arn = "arn:aws:sns:us-east-1:123456789012:rds-aurora-backup-automation-2-notifications"
backup_schedule = "cron(0 2 * * ? *)"
```

## 🗑️ Limpieza

### Destruir Infraestructura
```bash
# Destruir todos los recursos
terraform destroy

# Destruir recursos específicos
terraform destroy -target=aws_lambda_function.backup_lambda
```

### Limpiar Backups Manualmente
```bash
# Listar recovery points
aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name Default

# Eliminar recovery point específico
aws backup delete-recovery-point \
  --backup-vault-name Default \
  --recovery-point-arn <ARN>
```

## 📖 Referencias

- [AWS Backup Documentation](https://docs.aws.amazon.com/backup/)
- [Lambda Python Runtime](https://docs.aws.amazon.com/lambda/latest/dg/lambda-python.html)
- [EventBridge Cron Expressions](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-create-rule-schedule.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## 🤝 Contribución

Para mejoras o reportar issues:
1. Revisar logs de CloudWatch
2. Verificar configuración de tags
3. Validar permisos IAM
4. Consultar documentación de AWS Backup

---

**Nota**: Este proyecto está diseñado para entornos de producción con mejores prácticas de seguridad, monitoreo y manejo de errores. Siempre prueba en un ambiente de desarrollo primero.