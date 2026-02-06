import boto3
import os
import json
from datetime import datetime, timedelta
from botocore.exceptions import ClientError
import logging

# Configuración de logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Clientes AWS
backup_client = boto3.client('backup')
rds_client = boto3.client('rds')

# Variables de entorno
BACKUP_VAULT_NAME = os.environ.get('BACKUP_VAULT_NAME', 'Default')
RETENTION_DAYS = int(os.environ.get('RETENTION_DAYS', '5'))
BACKUP_TAG_KEY = os.environ.get('BACKUP_TAG_KEY', 'Backup')
BACKUP_TAG_VALUE = os.environ.get('BACKUP_TAG_VALUE', 'True')
IAM_ROLE_ARN = os.environ['BACKUP_ROLE_ARN']

def lambda_handler(event, context):
    """
    Función principal que orquesta el proceso de backup
    """
    try:
        logger.info("Iniciando proceso de backup automatizado")
        
        # Obtener instancias RDS y clusters Aurora con el tag especificado
        rds_instances = get_tagged_rds_instances()
        aurora_clusters = get_tagged_aurora_clusters()
        
        backup_results = {
            'successful': [],
            'failed': [],
            'total_processed': 0
        }
        
        # Procesar instancias RDS
        for instance in rds_instances:
            result = create_rds_backup(instance)
            backup_results['total_processed'] += 1
            if result['success']:
                backup_results['successful'].append(result)
            else:
                backup_results['failed'].append(result)
        
        # Procesar clusters Aurora
        for cluster in aurora_clusters:
            result = create_aurora_backup(cluster)
            backup_results['total_processed'] += 1
            if result['success']:
                backup_results['successful'].append(result)
            else:
                backup_results['failed'].append(result)
        
        # Log de resultados
        logger.info(f"Proceso completado: {len(backup_results['successful'])} exitosos, "
                   f"{len(backup_results['failed'])} fallidos de "
                   f"{backup_results['total_processed']} total")
        
        return {
            'statusCode': 200,
            'body': json.dumps(backup_results, default=str)
        }
        
    except Exception as e:
        logger.error(f"Error crítico en lambda_handler: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def get_tagged_rds_instances():
    """
    Obtiene todas las instancias RDS con el tag específico
    """
    tagged_instances = []
    
    try:
        paginator = rds_client.get_paginator('describe_db_instances')
        
        for page in paginator.paginate():
            for instance in page['DBInstances']:
                instance_arn = instance['DBInstanceArn']
                
                # Obtener tags de la instancia
                tags_response = rds_client.list_tags_for_resource(
                    ResourceName=instance_arn
                )
                
                # Verificar si tiene el tag correcto
                for tag in tags_response.get('TagList', []):
                    if (tag['Key'] == BACKUP_TAG_KEY and 
                        tag['Value'] == BACKUP_TAG_VALUE):
                        tagged_instances.append({
                            'arn': instance_arn,
                            'identifier': instance['DBInstanceIdentifier'],
                            'engine': instance['Engine']
                        })
                        logger.info(f"RDS encontrada: {instance['DBInstanceIdentifier']}")
                        break
        
        logger.info(f"Total de instancias RDS etiquetadas: {len(tagged_instances)}")
        return tagged_instances
        
    except ClientError as e:
        logger.error(f"Error obteniendo instancias RDS: {str(e)}")
        return []

def get_tagged_aurora_clusters():
    """
    Obtiene todos los clusters Aurora con el tag específico
    """
    tagged_clusters = []
    
    try:
        paginator = rds_client.get_paginator('describe_db_clusters')
        
        for page in paginator.paginate():
            for cluster in page['DBClusters']:
                cluster_arn = cluster['DBClusterArn']
                
                # Obtener tags del cluster
                tags_response = rds_client.list_tags_for_resource(
                    ResourceName=cluster_arn
                )
                
                # Verificar si tiene el tag correcto
                for tag in tags_response.get('TagList', []):
                    if (tag['Key'] == BACKUP_TAG_KEY and 
                        tag['Value'] == BACKUP_TAG_VALUE):
                        tagged_clusters.append({
                            'arn': cluster_arn,
                            'identifier': cluster['DBClusterIdentifier'],
                            'engine': cluster['Engine']
                        })
                        logger.info(f"Aurora Cluster encontrado: {cluster['DBClusterIdentifier']}")
                        break
        
        logger.info(f"Total de clusters Aurora etiquetados: {len(tagged_clusters)}")
        return tagged_clusters
        
    except ClientError as e:
        logger.error(f"Error obteniendo clusters Aurora: {str(e)}")
        return []

def create_rds_backup(instance):
    """
    Crea un backup on-demand de una instancia RDS usando AWS Backup
    """
    backup_job_id = None
    
    try:
        timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
        backup_name = f"rds-{instance['identifier']}-{timestamp}"
        
        # Calcular fecha de expiración
        completion_date = datetime.now() + timedelta(days=RETENTION_DAYS)
        
        # Iniciar backup job
        response = backup_client.start_backup_job(
            BackupVaultName=BACKUP_VAULT_NAME,
            ResourceArn=instance['arn'],
            IamRoleArn=IAM_ROLE_ARN,
            IdempotencyToken=backup_name,
            Lifecycle={
                'DeleteAfterDays': RETENTION_DAYS
            },
            RecoveryPointTags={
                'Name': backup_name,
                'ResourceType': 'RDS',
                'Engine': instance['engine'],
                'AutomatedBackup': 'True',
                'CreatedBy': 'Lambda'
            }
        )
        
        backup_job_id = response['BackupJobId']
        
        logger.info(f"Backup iniciado para RDS {instance['identifier']}: {backup_job_id}")
        
        return {
            'success': True,
            'resource': instance['identifier'],
            'type': 'RDS',
            'backup_job_id': backup_job_id,
            'backup_name': backup_name
        }
        
    except ClientError as e:
        error_msg = str(e)
        logger.error(f"Error creando backup para RDS {instance['identifier']}: {error_msg}")
        
        return {
            'success': False,
            'resource': instance['identifier'],
            'type': 'RDS',
            'error': error_msg
        }

def create_aurora_backup(cluster):
    """
    Crea un backup on-demand de un cluster Aurora usando AWS Backup
    """
    backup_job_id = None
    
    try:
        timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
        backup_name = f"aurora-{cluster['identifier']}-{timestamp}"
        
        # Calcular fecha de expiración
        completion_date = datetime.now() + timedelta(days=RETENTION_DAYS)
        
        # Iniciar backup job
        response = backup_client.start_backup_job(
            BackupVaultName=BACKUP_VAULT_NAME,
            ResourceArn=cluster['arn'],
            IamRoleArn=IAM_ROLE_ARN,
            IdempotencyToken=backup_name,
            Lifecycle={
                'DeleteAfterDays': RETENTION_DAYS
            },
            RecoveryPointTags={
                'Name': backup_name,
                'ResourceType': 'Aurora',
                'Engine': cluster['engine'],
                'AutomatedBackup': 'True',
                'CreatedBy': 'Lambda'
            }
        )
        
        backup_job_id = response['BackupJobId']
        
        logger.info(f"Backup iniciado para Aurora {cluster['identifier']}: {backup_job_id}")
        
        return {
            'success': True,
            'resource': cluster['identifier'],
            'type': 'Aurora',
            'backup_job_id': backup_job_id,
            'backup_name': backup_name
        }
        
    except ClientError as e:
        error_msg = str(e)
        logger.error(f"Error creando backup para Aurora {cluster['identifier']}: {error_msg}")
        
        return {
            'success': False,
            'resource': cluster['identifier'],
            'type': 'Aurora',
            'error': error_msg
        }