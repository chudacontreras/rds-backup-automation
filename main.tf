terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  profile = "default" #colaocar el propfile de AWS 
}

# Data source para verificar si el vault existe (puede fallar)
data "aws_backup_vault" "existing" {
  count = var.use_existing_vault ? 1 : 0
  name  = var.backup_vault_name
}

# KMS Key (solo si creamos un nuevo vault)
resource "aws_kms_key" "backup_vault_key" {
  count                   = var.use_existing_vault ? 0 : 1
  description             = "KMS key for ${var.backup_vault_name} backup vault"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${var.backup_vault_name}-kms-key"
  })
}

resource "aws_kms_alias" "backup_vault_key_alias" {
  count         = var.use_existing_vault ? 0 : 1
  name          = "alias/${var.backup_vault_name}-backup-vault"
  target_key_id = aws_kms_key.backup_vault_key[0].key_id
}

# Crear Backup Vault solo si no existe
resource "aws_backup_vault" "new" {
  count       = var.use_existing_vault ? 0 : 1
  name        = var.backup_vault_name
  kms_key_arn = aws_kms_key.backup_vault_key[0].arn

  tags = merge(var.tags, {
    Name = var.backup_vault_name
  })
}

# Local value para determinar qué vault usar
locals {
  backup_vault_name = var.use_existing_vault ? data.aws_backup_vault.existing[0].name : aws_backup_vault.new[0].name
  backup_vault_arn  = var.use_existing_vault ? data.aws_backup_vault.existing[0].arn : aws_backup_vault.new[0].arn
}

# IAM Role para AWS Backup
resource "aws_iam_role" "backup_role" {
  name               = "${var.lambda_function_name}-backup-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "backup.amazonaws.com"
      }
    }]
  })

  tags = merge(var.tags, {
    Name = "${var.lambda_function_name}-backup-role"
  })
}

resource "aws_iam_role_policy_attachment" "backup_policy" {
  role       = aws_iam_role.backup_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "restore_policy" {
  role       = aws_iam_role.backup_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# IAM Role para Lambda
resource "aws_iam_role" "lambda_role" {
  name               = "${var.lambda_function_name}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = merge(var.tags, {
    Name = "${var.lambda_function_name}-lambda-role"
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.lambda_function_name}-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:DescribeDBClusters",
          "rds:ListTagsForResource"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "backup:StartBackupJob",
          "backup:DescribeBackupVault",
          "backup:ListBackupJobs",
          "backup:ListRecoveryPointsByBackupVault"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.backup_role.arn
      }
    ]
  })
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.lambda_function_name}"
  retention_in_days = 14

  tags = merge(var.tags, {
    Name = "${var.lambda_function_name}-logs"
  })
}

# Lambda Function con código inline
resource "aws_lambda_function" "backup_lambda" {
  function_name = var.lambda_function_name
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.lambda_handler"
  runtime       = "python3.11"
  timeout       = 900
  memory_size   = 256

  filename         = data.archive_file.lambda_inline.output_path
  source_code_hash = data.archive_file.lambda_inline.output_base64sha256

  environment {
    variables = {
      BACKUP_VAULT_NAME  = local.backup_vault_name
      RETENTION_DAYS     = var.retention_days
      BACKUP_TAG_KEY     = var.backup_tag_key
      BACKUP_TAG_VALUE   = var.backup_tag_value
      BACKUP_ROLE_ARN    = aws_iam_role.backup_role.arn
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda_logs,
    aws_iam_role_policy.lambda_policy
  ]

  tags = merge(var.tags, {
    Name = var.lambda_function_name
  })
}

# Crear archivo temporal y empaquetarlo
data "archive_file" "lambda_inline" {
  type        = "zip"
  output_path = "${path.module}/lambda_payload.zip"

  source {
    content  = <<-EOT
import boto3
import os
import json
from datetime import datetime, timedelta
from botocore.exceptions import ClientError
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

backup_client = boto3.client('backup')
rds_client = boto3.client('rds')

BACKUP_VAULT_NAME = os.environ.get('BACKUP_VAULT_NAME', 'Default')
RETENTION_DAYS = int(os.environ.get('RETENTION_DAYS', '5'))
BACKUP_TAG_KEY = os.environ.get('BACKUP_TAG_KEY', 'Backup')
BACKUP_TAG_VALUE = os.environ.get('BACKUP_TAG_VALUE', 'True')
IAM_ROLE_ARN = os.environ['BACKUP_ROLE_ARN']

def lambda_handler(event, context):
    try:
        logger.info("=" * 60)
        logger.info("🚀 INICIANDO BACKUP AUTOMATIZADO")
        logger.info(f"📦 Vault: {BACKUP_VAULT_NAME}")
        logger.info(f"⏰ Retención: {RETENTION_DAYS} días")
        logger.info(f"🏷️  Tag: {BACKUP_TAG_KEY}={BACKUP_TAG_VALUE}")
        logger.info("=" * 60)
        
        rds_instances = get_tagged_rds_instances()
        aurora_clusters = get_tagged_aurora_clusters()
        
        total_resources = len(rds_instances) + len(aurora_clusters)
        
        if total_resources == 0:
            logger.warning("⚠️  No se encontraron recursos con el tag especificado")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'No resources found with specified tags',
                    'tag_key': BACKUP_TAG_KEY,
                    'tag_value': BACKUP_TAG_VALUE
                })
            }
        
        backup_results = {
            'successful': [],
            'failed': [],
            'total_processed': 0,
            'timestamp': datetime.now().isoformat(),
            'vault': BACKUP_VAULT_NAME,
            'retention_days': RETENTION_DAYS
        }
        
        for instance in rds_instances:
            result = create_rds_backup(instance)
            backup_results['total_processed'] += 1
            backup_results['successful' if result['success'] else 'failed'].append(result)
        
        for cluster in aurora_clusters:
            result = create_aurora_backup(cluster)
            backup_results['total_processed'] += 1
            backup_results['successful' if result['success'] else 'failed'].append(result)
        
        logger.info("=" * 60)
        logger.info(f"✅ Exitosos: {len(backup_results['successful'])}")
        logger.info(f"❌ Fallidos: {len(backup_results['failed'])}")
        logger.info(f"📊 Total procesados: {backup_results['total_processed']}")
        logger.info("=" * 60)
        
        if backup_results['failed']:
            logger.warning("⚠️  RECURSOS CON FALLOS:")
            for fail in backup_results['failed']:
                logger.warning(f"  • {fail['resource']} ({fail['type']}): {fail.get('error', 'Unknown')}")
        
        if backup_results['successful']:
            logger.info("✅ BACKUPS EXITOSOS:")
            for success in backup_results['successful']:
                logger.info(f"  • {success['resource']} ({success['type']}): Job {success['backup_job_id']}")
        
        return {
            'statusCode': 200 if not backup_results['failed'] else 207,
            'body': json.dumps(backup_results, default=str, indent=2)
        }
        
    except Exception as e:
        logger.error(f"❌ ERROR CRÍTICO: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e), 'error_type': type(e).__name__})
        }

def get_tagged_rds_instances():
    tagged_instances = []
    try:
        logger.info("🔍 Buscando instancias RDS...")
        paginator = rds_client.get_paginator('describe_db_instances')
        
        for page in paginator.paginate():
            for instance in page['DBInstances']:
                try:
                    tags = rds_client.list_tags_for_resource(ResourceName=instance['DBInstanceArn'])
                    for tag in tags.get('TagList', []):
                        if tag['Key'] == BACKUP_TAG_KEY and tag['Value'] == BACKUP_TAG_VALUE:
                            tagged_instances.append({
                                'arn': instance['DBInstanceArn'],
                                'identifier': instance['DBInstanceIdentifier'],
                                'engine': instance['Engine']
                            })
                            logger.info(f"  ✓ RDS: {instance['DBInstanceIdentifier']} ({instance['Engine']})")
                            break
                except ClientError as e:
                    logger.debug(f"  ⚠️  No se pudieron leer tags de {instance.get('DBInstanceIdentifier', 'unknown')}: {str(e)}")
                    continue
                except Exception as e:
                    logger.debug(f"  ⚠️  Error inesperado: {str(e)}")
                    continue
        
        logger.info(f"📌 Total RDS encontradas: {len(tagged_instances)}")
        return tagged_instances
        
    except Exception as e:
        logger.error(f"❌ Error listando instancias RDS: {str(e)}")
        return []

def get_tagged_aurora_clusters():
    tagged_clusters = []
    try:
        logger.info("🔍 Buscando clusters Aurora...")
        paginator = rds_client.get_paginator('describe_db_clusters')
        
        for page in paginator.paginate():
            for cluster in page['DBClusters']:
                try:
                    tags = rds_client.list_tags_for_resource(ResourceName=cluster['DBClusterArn'])
                    for tag in tags.get('TagList', []):
                        if tag['Key'] == BACKUP_TAG_KEY and tag['Value'] == BACKUP_TAG_VALUE:
                            tagged_clusters.append({
                                'arn': cluster['DBClusterArn'],
                                'identifier': cluster['DBClusterIdentifier'],
                                'engine': cluster['Engine']
                            })
                            logger.info(f"  ✓ Aurora: {cluster['DBClusterIdentifier']} ({cluster['Engine']})")
                            break
                except ClientError as e:
                    logger.debug(f"  ⚠️  No se pudieron leer tags de {cluster.get('DBClusterIdentifier', 'unknown')}: {str(e)}")
                    continue
                except Exception as e:
                    logger.debug(f"  ⚠️  Error inesperado: {str(e)}")
                    continue
        
        logger.info(f"📌 Total Aurora encontrados: {len(tagged_clusters)}")
        return tagged_clusters
        
    except Exception as e:
        logger.error(f"❌ Error listando clusters Aurora: {str(e)}")
        return []

def create_rds_backup(instance):
    try:
        timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
        backup_name = f"rds-{instance['identifier']}-{timestamp}"
        
        logger.info(f"💾 Iniciando backup RDS: {instance['identifier']}")
        
        response = backup_client.start_backup_job(
            BackupVaultName=BACKUP_VAULT_NAME,
            ResourceArn=instance['arn'],
            IamRoleArn=IAM_ROLE_ARN,
            IdempotencyToken=backup_name,
            Lifecycle={'DeleteAfterDays': RETENTION_DAYS},
            RecoveryPointTags={
                'Name': backup_name,
                'ResourceType': 'RDS',
                'ResourceIdentifier': instance['identifier'],
                'Engine': instance['engine'],
                'AutomatedBackup': 'True',
                'CreatedBy': 'Lambda',
                'RetentionDays': str(RETENTION_DAYS),
                'BackupDate': datetime.now().isoformat()
            }
        )
        
        logger.info(f"  ✅ Job ID: {response['BackupJobId']}")
        
        return {
            'success': True,
            'resource': instance['identifier'],
            'type': 'RDS',
            'engine': instance['engine'],
            'backup_job_id': response['BackupJobId'],
            'backup_name': backup_name,
            'vault': BACKUP_VAULT_NAME,
            'retention_days': RETENTION_DAYS
        }
        
    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_msg = e.response['Error']['Message']
        logger.error(f"  ❌ Error [{error_code}]: {error_msg}")
        
        return {
            'success': False,
            'resource': instance['identifier'],
            'type': 'RDS',
            'error_code': error_code,
            'error': error_msg
        }
    except Exception as e:
        logger.error(f"  ❌ Error inesperado: {str(e)}")
        return {
            'success': False,
            'resource': instance['identifier'],
            'type': 'RDS',
            'error': str(e)
        }

def create_aurora_backup(cluster):
    try:
        timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
        backup_name = f"aurora-{cluster['identifier']}-{timestamp}"
        
        logger.info(f"💾 Iniciando backup Aurora: {cluster['identifier']}")
        
        response = backup_client.start_backup_job(
            BackupVaultName=BACKUP_VAULT_NAME,
            ResourceArn=cluster['arn'],
            IamRoleArn=IAM_ROLE_ARN,
            IdempotencyToken=backup_name,
            Lifecycle={'DeleteAfterDays': RETENTION_DAYS},
            RecoveryPointTags={
                'Name': backup_name,
                'ResourceType': 'Aurora',
                'ResourceIdentifier': cluster['identifier'],
                'Engine': cluster['engine'],
                'AutomatedBackup': 'True',
                'CreatedBy': 'Lambda',
                'RetentionDays': str(RETENTION_DAYS),
                'BackupDate': datetime.now().isoformat()
            }
        )
        
        logger.info(f"  ✅ Job ID: {response['BackupJobId']}")
        
        return {
            'success': True,
            'resource': cluster['identifier'],
            'type': 'Aurora',
            'engine': cluster['engine'],
            'backup_job_id': response['BackupJobId'],
            'backup_name': backup_name,
            'vault': BACKUP_VAULT_NAME,
            'retention_days': RETENTION_DAYS
        }
        
    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_msg = e.response['Error']['Message']
        logger.error(f"  ❌ Error [{error_code}]: {error_msg}")
        
        return {
            'success': False,
            'resource': cluster['identifier'],
            'type': 'Aurora',
            'error_code': error_code,
            'error': error_msg
        }
    except Exception as e:
        logger.error(f"  ❌ Error inesperado: {str(e)}")
        return {
            'success': False,
            'resource': cluster['identifier'],
            'type': 'Aurora',
            'error': str(e)
        }
EOT
    filename = "index.py"
  }
}

# EventBridge Rule
resource "aws_cloudwatch_event_rule" "backup_schedule" {
  name                = "${var.lambda_function_name}-schedule"
  description         = "Trigger backup Lambda on schedule"
  schedule_expression = var.backup_schedule

  tags = merge(var.tags, {
    Name = "${var.lambda_function_name}-schedule"
  })
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.backup_schedule.name
  target_id = "BackupLambda"
  arn       = aws_lambda_function.backup_lambda.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.backup_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.backup_schedule.arn
}

# SNS Topic
resource "aws_sns_topic" "backup_notifications" {
  name = "${var.lambda_function_name}-notifications"

  tags = merge(var.tags, {
    Name = "${var.lambda_function_name}-notifications"
  })
}

# CloudWatch Alarm
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.lambda_function_name}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Alerta cuando la función Lambda falla"
  alarm_actions       = [aws_sns_topic.backup_notifications.arn]

  dimensions = {
    FunctionName = aws_lambda_function.backup_lambda.function_name
  }

  tags = merge(var.tags, {
    Name = "${var.lambda_function_name}-error-alarm"
  })
}