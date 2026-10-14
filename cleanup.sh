#!/bin/bash
# Script para eliminar todos los recursos AWS creados
# Ejecutar cuando ya no necesites el proyecto
set -e
if [ -f "config.sh" ]; then
  source config.sh
elif [ -f "config.sh.example" ]; then
  source config.sh.example
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "ADVERTENCIA: Esto eliminara TODOS los recursos del examen01 en AWS"
read -p "Continuar? (y/N): " CONFIRM
if [ "$CONFIRM" != "y" ]; then echo "Cancelado"; exit 0; fi

echo ">>> Eliminando API Gateway..."
API_ID=$(aws apigateway get-rest-apis \
  --query "items[?name=='${PROJECT_PREFIX}-api'].id" --output text \
  --region $AWS_REGION 2>/dev/null)
if [ -n "$API_ID" ] && [ "$API_ID" != "None" ]; then
  aws apigateway delete-rest-api --rest-api-id $API_ID --region $AWS_REGION
fi

echo ">>> Eliminando event source mappings de SQS..."
for UUID in $(aws lambda list-event-source-mappings \
  --function-name ${PROJECT_PREFIX}-sqs_trigger \
  --query 'EventSourceMappings[].UUID' --output text \
  --region $AWS_REGION 2>/dev/null); do
  aws lambda delete-event-source-mapping --uuid $UUID --region $AWS_REGION
done

echo ">>> Eliminando Step Function..."
aws stepfunctions delete-state-machine \
  --state-machine-arn arn:aws:states:${AWS_REGION}:${ACCOUNT_ID}:stateMachine:${PROJECT_PREFIX}-nota-workflow \
  --region $AWS_REGION 2>/dev/null || true

echo ">>> Eliminando Lambdas..."
for FUNC in clientes domicilios productos notas generar_pdf subir_s3 enviar_email sqs_trigger; do
  aws lambda delete-function --function-name ${PROJECT_PREFIX}-${FUNC} --region $AWS_REGION 2>/dev/null || true
done

echo ">>> Eliminando Lambda Layer..."
for VERSION in $(aws lambda list-layer-versions \
  --layer-name ${PROJECT_PREFIX}-deps \
  --query 'LayerVersions[].Version' --output text \
  --region $AWS_REGION 2>/dev/null); do
  aws lambda delete-layer-version --layer-name ${PROJECT_PREFIX}-deps --version-number $VERSION --region $AWS_REGION
done

echo ">>> Vaciando y eliminando S3 bucket..."
aws s3 rb s3://$S3_BUCKET --force --region $AWS_REGION 2>/dev/null || true

echo ">>> Eliminando SQS queue..."
QUEUE_URL=$(aws sqs get-queue-url --queue-name ${PROJECT_PREFIX}-notas-queue \
  --query 'QueueUrl' --output text --region $AWS_REGION 2>/dev/null) || true
if [ -n "$QUEUE_URL" ] && [ "$QUEUE_URL" != "None" ]; then
  aws sqs delete-queue --queue-url $QUEUE_URL --region $AWS_REGION
fi

echo ">>> Eliminando RDS..."
aws rds delete-db-instance \
  --db-instance-identifier ${PROJECT_PREFIX}-db \
  --skip-final-snapshot \
  --region $AWS_REGION 2>/dev/null || true

echo ">>> Eliminando Security Group (esperando que RDS se elimine)..."
echo "  Nota: El security group se eliminara cuando RDS termine de borrarse."
echo "  Puedes eliminarlo manualmente despues con:"
echo "  aws ec2 delete-security-group --group-name ${PROJECT_PREFIX}-rds-sg --region $AWS_REGION"

echo ">>> Eliminando IAM Role..."
for POLICY in \
  arn:aws:iam::aws:policy/AmazonRDSDataFullAccess \
  arn:aws:iam::aws:policy/AmazonS3FullAccess \
  arn:aws:iam::aws:policy/AmazonSESFullAccess \
  arn:aws:iam::aws:policy/AmazonSQSFullAccess \
  arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess \
  arn:aws:iam::aws:policy/AWSLambda_FullAccess \
  arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole; do
  aws iam detach-role-policy --role-name ${PROJECT_PREFIX}-lambda-role --policy-arn $POLICY 2>/dev/null || true
done
aws iam delete-role --role-name ${PROJECT_PREFIX}-lambda-role 2>/dev/null || true

echo ""
echo "Limpieza completa. RDS puede tardar unos minutos en eliminarse."
