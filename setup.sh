#!/bin/bash
set -e
if [ -f "config.sh" ]; then
  source config.sh
elif [ -f "config.sh.example" ]; then
  echo "config.sh not found. Copying config.sh.example to config.sh..."
  cp config.sh.example config.sh
  source config.sh
else
  echo "Error: config.sh not found."
  exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: $ACCOUNT_ID"
echo "Region: $AWS_REGION"

# ============================================
# 1. IAM ROLE PARA LAMBDAS
# ============================================
echo ">>> Creando IAM Role..."

TRUST_POLICY='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"Service": ["lambda.amazonaws.com", "states.amazonaws.com"]},
      "Action": "sts:AssumeRole"
    }
  ]
}'

aws iam create-role \
  --role-name ${PROJECT_PREFIX}-lambda-role \
  --assume-role-policy-document "$TRUST_POLICY" \
  --region $AWS_REGION 2>/dev/null || echo "Role ya existe"

for POLICY in \
  arn:aws:iam::aws:policy/AmazonRDSDataFullAccess \
  arn:aws:iam::aws:policy/AmazonS3FullAccess \
  arn:aws:iam::aws:policy/AmazonSESFullAccess \
  arn:aws:iam::aws:policy/AmazonSQSFullAccess \
  arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess \
  arn:aws:iam::aws:policy/AWSLambda_FullAccess \
  arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole; do
  aws iam attach-role-policy --role-name ${PROJECT_PREFIX}-lambda-role --policy-arn $POLICY 2>/dev/null || true
done

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${PROJECT_PREFIX}-lambda-role"
echo "Role ARN: $ROLE_ARN"
echo "Esperando 10s para que IAM propague el rol..."
sleep 10

# ============================================
# 2. RDS MYSQL
# ============================================
echo ">>> Creando RDS MySQL..."

# Security Group para RDS
SG_ID=$(aws ec2 create-security-group \
  --group-name ${PROJECT_PREFIX}-rds-sg \
  --description "RDS access for examen01" \
  --query 'GroupId' --output text \
  --region $AWS_REGION 2>/dev/null) || \
SG_ID=$(aws ec2 describe-security-groups \
  --filters Name=group-name,Values=${PROJECT_PREFIX}-rds-sg \
  --query 'SecurityGroups[0].GroupId' --output text \
  --region $AWS_REGION)

aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp --port 3306 --cidr 0.0.0.0/0 \
  --region $AWS_REGION 2>/dev/null || true

echo "Security Group: $SG_ID"

aws rds create-db-instance \
  --db-instance-identifier ${PROJECT_PREFIX}-db \
  --db-instance-class db.t3.micro \
  --engine mysql \
  --engine-version "8.0" \
  --master-username $DB_USER \
  --master-user-password $DB_PASSWORD \
  --allocated-storage 20 \
  --db-name $DB_NAME \
  --vpc-security-group-ids $SG_ID \
  --publicly-accessible \
  --backup-retention-period 0 \
  --no-multi-az \
  --region $AWS_REGION 2>/dev/null || echo "RDS ya existe"

echo "Esperando a que RDS este disponible (esto toma ~5-10 min)..."
aws rds wait db-instance-available \
  --db-instance-identifier ${PROJECT_PREFIX}-db \
  --region $AWS_REGION

DB_HOST=$(aws rds describe-db-instances \
  --db-instance-identifier ${PROJECT_PREFIX}-db \
  --query 'DBInstances[0].Endpoint.Address' --output text \
  --region $AWS_REGION)
echo "RDS Endpoint: $DB_HOST"

# ============================================
# 3. INICIALIZAR BASE DE DATOS
# ============================================
echo ">>> Inicializando tablas en RDS..."
mysql -h $DB_HOST -u $DB_USER -p"$DB_PASSWORD" < sql/init.sql
echo "Tablas creadas"

# ============================================
# 4. S3 BUCKET
# ============================================
echo ">>> Creando bucket S3..."
aws s3 mb s3://$S3_BUCKET --region $AWS_REGION 2>/dev/null || echo "Bucket ya existe"

# ============================================
# 5. SQS QUEUE
# ============================================
echo ">>> Creando cola SQS..."
QUEUE_URL=$(aws sqs create-queue \
  --queue-name ${PROJECT_PREFIX}-notas-queue \
  --attributes VisibilityTimeout=300 \
  --query 'QueueUrl' --output text \
  --region $AWS_REGION)
echo "Queue URL: $QUEUE_URL"

QUEUE_ARN=$(aws sqs get-queue-attributes \
  --queue-url $QUEUE_URL \
  --attribute-names QueueArn \
  --query 'Attributes.QueueArn' --output text \
  --region $AWS_REGION)

# ============================================
# 6. SES - VERIFICAR EMAIL
# ============================================
echo ">>> Verificando email en SES..."
aws ses verify-email-identity \
  --email-address $SES_SENDER \
  --region $AWS_REGION
echo "Revisa tu correo ($SES_SENDER) y haz clic en el enlace de verificacion"

# ============================================
# 7. LAMBDA LAYER (dependencias)
# ============================================
echo ">>> Construyendo Lambda Layer..."
rm -rf /tmp/lambda-layer
mkdir -p /tmp/lambda-layer/python
pip install pymysql fpdf2 -t /tmp/lambda-layer/python --quiet
cp -r lambdas/shared /tmp/lambda-layer/python/
cd /tmp/lambda-layer
zip -r9 /tmp/layer.zip python/ --quiet
cd -

LAYER_ARN=$(aws lambda publish-layer-version \
  --layer-name ${PROJECT_PREFIX}-deps \
  --zip-file fileb:///tmp/layer.zip \
  --compatible-runtimes python3.12 \
  --query 'LayerVersionArn' --output text \
  --region $AWS_REGION)
echo "Layer ARN: $LAYER_ARN"

# ============================================
# 8. CREAR LAMBDAS
# ============================================
echo ">>> Creando Lambda functions..."

create_lambda() {
  local NAME=$1
  local EXTRA_ENV=$2

  local ENV_VARS="DB_HOST=$DB_HOST,DB_USER=$DB_USER,DB_PASSWORD=$DB_PASSWORD,DB_NAME=$DB_NAME"
  if [ -n "$EXTRA_ENV" ]; then
    ENV_VARS="$ENV_VARS,$EXTRA_ENV"
  fi

  # Empaquetar
  rm -f /tmp/${NAME}.zip
  cd lambdas/${NAME}
  zip /tmp/${NAME}.zip handler.py --quiet
  cd - > /dev/null

  # Crear o actualizar
  aws lambda create-function \
    --function-name ${PROJECT_PREFIX}-${NAME} \
    --runtime python3.12 \
    --role $ROLE_ARN \
    --handler handler.handler \
    --zip-file fileb:///tmp/${NAME}.zip \
    --timeout 30 \
    --layers $LAYER_ARN \
    --environment "Variables={$ENV_VARS}" \
    --region $AWS_REGION 2>/dev/null || \
  aws lambda update-function-code \
    --function-name ${PROJECT_PREFIX}-${NAME} \
    --zip-file fileb:///tmp/${NAME}.zip \
    --region $AWS_REGION > /dev/null

  echo "  Lambda ${PROJECT_PREFIX}-${NAME} creada"
}

create_lambda "clientes" ""
create_lambda "domicilios" ""
create_lambda "productos" ""
create_lambda "notas" "SQS_QUEUE_URL=$QUEUE_URL,S3_BUCKET=$S3_BUCKET,SES_SENDER=$SES_SENDER,API_BASE_URL=PENDING"
create_lambda "generar_pdf" ""
create_lambda "subir_s3" "S3_BUCKET=$S3_BUCKET"
create_lambda "enviar_email" "S3_BUCKET=$S3_BUCKET,SES_SENDER=$SES_SENDER,API_BASE_URL=PENDING"
create_lambda "sqs_trigger" "STATE_MACHINE_ARN=PENDING"

# ============================================
# 9. STEP FUNCTION
# ============================================
echo ">>> Creando Step Function..."

STATE_MACHINE_DEF=$(cat <<EOF
{
  "Comment": "Procesar nota de venta",
  "StartAt": "GenerarPDF",
  "States": {
    "GenerarPDF": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:${AWS_REGION}:${ACCOUNT_ID}:function:${PROJECT_PREFIX}-generar_pdf",
      "Next": "SubirS3"
    },
    "SubirS3": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:${AWS_REGION}:${ACCOUNT_ID}:function:${PROJECT_PREFIX}-subir_s3",
      "Next": "EnviarEmail"
    },
    "EnviarEmail": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:${AWS_REGION}:${ACCOUNT_ID}:function:${PROJECT_PREFIX}-enviar_email",
      "End": true
    }
  }
}
EOF
)

STATE_MACHINE_ARN=$(aws stepfunctions create-state-machine \
  --name ${PROJECT_PREFIX}-nota-workflow \
  --definition "$STATE_MACHINE_DEF" \
  --role-arn $ROLE_ARN \
  --query 'stateMachineArn' --output text \
  --region $AWS_REGION 2>/dev/null) || \
STATE_MACHINE_ARN=$(aws stepfunctions describe-state-machine \
  --state-machine-arn arn:aws:states:${AWS_REGION}:${ACCOUNT_ID}:stateMachine:${PROJECT_PREFIX}-nota-workflow \
  --query 'stateMachineArn' --output text \
  --region $AWS_REGION)

echo "State Machine ARN: $STATE_MACHINE_ARN"

# Actualizar sqs_trigger con el ARN real
aws lambda update-function-configuration \
  --function-name ${PROJECT_PREFIX}-sqs_trigger \
  --environment "Variables={STATE_MACHINE_ARN=$STATE_MACHINE_ARN,DB_HOST=$DB_HOST,DB_USER=$DB_USER,DB_PASSWORD=$DB_PASSWORD,DB_NAME=$DB_NAME}" \
  --region $AWS_REGION > /dev/null

# ============================================
# 10. TRIGGER SQS -> LAMBDA
# ============================================
echo ">>> Conectando SQS a Lambda sqs_trigger..."
aws lambda create-event-source-mapping \
  --function-name ${PROJECT_PREFIX}-sqs_trigger \
  --event-source-arn $QUEUE_ARN \
  --batch-size 1 \
  --region $AWS_REGION 2>/dev/null || echo "Trigger SQS ya existe"

# ============================================
# 11. API GATEWAY
# ============================================
echo ">>> Creando API Gateway..."

API_ID=$(aws apigateway create-rest-api \
  --name ${PROJECT_PREFIX}-api \
  --endpoint-configuration types=REGIONAL \
  --query 'id' --output text \
  --region $AWS_REGION)
echo "API ID: $API_ID"

ROOT_ID=$(aws apigateway get-resources \
  --rest-api-id $API_ID \
  --query 'items[?path==`/`].id' --output text \
  --region $AWS_REGION)

# Funcion helper para crear recurso
create_resource() {
  local PARENT_ID=$1
  local PATH_PART=$2
  aws apigateway create-resource \
    --rest-api-id $API_ID \
    --parent-id $PARENT_ID \
    --path-part "$PATH_PART" \
    --query 'id' --output text \
    --region $AWS_REGION
}

# Funcion helper para crear metodo + integracion Lambda proxy
create_method() {
  local RESOURCE_ID=$1
  local HTTP_METHOD=$2
  local LAMBDA_NAME=$3

  local LAMBDA_ARN="arn:aws:lambda:${AWS_REGION}:${ACCOUNT_ID}:function:${PROJECT_PREFIX}-${LAMBDA_NAME}"
  local LAMBDA_URI="arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations"

  aws apigateway put-method \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method $HTTP_METHOD \
    --authorization-type NONE \
    --region $AWS_REGION > /dev/null

  aws apigateway put-integration \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method $HTTP_METHOD \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri $LAMBDA_URI \
    --region $AWS_REGION > /dev/null

  # Permiso para que API Gateway invoque la Lambda
  aws lambda add-permission \
    --function-name ${PROJECT_PREFIX}-${LAMBDA_NAME} \
    --statement-id "apigateway-${RESOURCE_ID}-${HTTP_METHOD}" \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:${AWS_REGION}:${ACCOUNT_ID}:${API_ID}/*/${HTTP_METHOD}/*" \
    --region $AWS_REGION 2>/dev/null || true
}

echo "  Creando recursos y metodos..."

# /clientes
RES_CLIENTES=$(create_resource $ROOT_ID "clientes")
create_method $RES_CLIENTES POST clientes
create_method $RES_CLIENTES GET clientes

# /clientes/{id}
RES_CLIENTES_ID=$(create_resource $RES_CLIENTES "{id}")
create_method $RES_CLIENTES_ID GET clientes
create_method $RES_CLIENTES_ID PUT clientes
create_method $RES_CLIENTES_ID DELETE clientes

# /clientes/{id}/domicilios
RES_DOMICILIOS_NEST=$(create_resource $RES_CLIENTES_ID "domicilios")
create_method $RES_DOMICILIOS_NEST POST domicilios
create_method $RES_DOMICILIOS_NEST GET domicilios

# /domicilios
RES_DOMICILIOS=$(create_resource $ROOT_ID "domicilios")

# /domicilios/{domicilioId}
RES_DOMICILIOS_ID=$(create_resource $RES_DOMICILIOS "{domicilioId}")
create_method $RES_DOMICILIOS_ID GET domicilios
create_method $RES_DOMICILIOS_ID PUT domicilios
create_method $RES_DOMICILIOS_ID DELETE domicilios

# /productos
RES_PRODUCTOS=$(create_resource $ROOT_ID "productos")
create_method $RES_PRODUCTOS POST productos
create_method $RES_PRODUCTOS GET productos

# /productos/{id}
RES_PRODUCTOS_ID=$(create_resource $RES_PRODUCTOS "{id}")
create_method $RES_PRODUCTOS_ID GET productos
create_method $RES_PRODUCTOS_ID PUT productos
create_method $RES_PRODUCTOS_ID DELETE productos

# /notas
RES_NOTAS=$(create_resource $ROOT_ID "notas")
create_method $RES_NOTAS POST notas

# /notas/{id}
RES_NOTAS_ID=$(create_resource $RES_NOTAS "{id}")
create_method $RES_NOTAS_ID GET notas

# /notas/{id}/pdf
RES_NOTAS_PDF=$(create_resource $RES_NOTAS_ID "pdf")
create_method $RES_NOTAS_PDF GET notas

# /notas/{id}/enviar
RES_NOTAS_ENVIAR=$(create_resource $RES_NOTAS_ID "enviar")
create_method $RES_NOTAS_ENVIAR POST notas

# Configurar Binary Media Types para PDF
aws apigateway update-rest-api \
  --rest-api-id $API_ID \
  --patch-operations op=add,path=/binaryMediaTypes/application~1pdf \
  --region $AWS_REGION > /dev/null

# Deploy
echo "  Desplegando API..."
aws apigateway create-deployment \
  --rest-api-id $API_ID \
  --stage-name prod \
  --region $AWS_REGION > /dev/null

API_BASE_URL="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod"
echo "API URL: $API_BASE_URL"

# ============================================
# 12. ACTUALIZAR LAMBDAS CON API_BASE_URL
# ============================================
echo ">>> Actualizando Lambdas con la URL del API..."

aws lambda update-function-configuration \
  --function-name ${PROJECT_PREFIX}-notas \
  --environment "Variables={DB_HOST=$DB_HOST,DB_USER=$DB_USER,DB_PASSWORD=$DB_PASSWORD,DB_NAME=$DB_NAME,SQS_QUEUE_URL=$QUEUE_URL,S3_BUCKET=$S3_BUCKET,SES_SENDER=$SES_SENDER,API_BASE_URL=$API_BASE_URL}" \
  --region $AWS_REGION > /dev/null

aws lambda update-function-configuration \
  --function-name ${PROJECT_PREFIX}-enviar_email \
  --environment "Variables={DB_HOST=$DB_HOST,DB_USER=$DB_USER,DB_PASSWORD=$DB_PASSWORD,DB_NAME=$DB_NAME,S3_BUCKET=$S3_BUCKET,SES_SENDER=$SES_SENDER,API_BASE_URL=$API_BASE_URL}" \
  --region $AWS_REGION > /dev/null

# ============================================
# RESUMEN
# ============================================
echo ""
echo "=========================================="
echo " SETUP COMPLETO"
echo "=========================================="
echo "API URL:        $API_BASE_URL"
echo "RDS Endpoint:   $DB_HOST"
echo "S3 Bucket:      $S3_BUCKET"
echo "SQS Queue:      $QUEUE_URL"
echo "Step Function:  $STATE_MACHINE_ARN"
echo ""
echo "IMPORTANTE: Verifica tu correo ($SES_SENDER) para confirmar SES"
echo ""
echo "Prueba con:"
echo "  curl -X POST $API_BASE_URL/clientes \\"
echo "    -H 'Content-Type: application/json' \\"
echo '    -d '"'"'{"razon_social":"Test SA","nombre_comercial":"Test","rfc":"TST123456789","email":"'$SES_SENDER'","telefono":"3312345678"}'"'"
echo "=========================================="
