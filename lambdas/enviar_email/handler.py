import os
from datetime import datetime
import boto3

ses = boto3.client('ses')
s3 = boto3.client('s3')

BUCKET = os.environ['S3_BUCKET']
API_BASE_URL = os.environ['API_BASE_URL']
SES_SENDER = os.environ['SES_SENDER']


def handler(event, context):
    nota_id = event['nota_id']
    folio = event['folio']
    email = event['email']
    nombre = event['nombre_comercial']
    s3_key = event['s3_key']

    download_url = f"{API_BASE_URL}/notas/{nota_id}/pdf"

    ses.send_email(
        Source=SES_SENDER,
        Destination={'ToAddresses': [email]},
        Message={
            'Subject': {'Data': f'Nota de Venta {folio}'},
            'Body': {
                'Html': {'Data': f"""
                    <h2>Nota de Venta</h2>
                    <p>Estimado {nombre},</p>
                    <p>Se ha generado su nota de venta con folio <b>{folio}</b>.</p>
                    <p><a href="{download_url}">Descargar Nota en PDF</a></p>
                """}
            }
        }
    )

    # Actualizar hora-envio despues de enviar
    obj = s3.head_object(Bucket=BUCKET, Key=s3_key)
    s3.copy_object(
        Bucket=BUCKET,
        CopySource={'Bucket': BUCKET, 'Key': s3_key},
        Key=s3_key,
        Metadata={
            'hora-envio': datetime.now().isoformat(),
            'nota-descargada': 'false',
            'veces-enviado': obj['Metadata'].get('veces-enviado', '1')
        },
        MetadataDirective='REPLACE'
    )

    return {'message': 'Email enviado', 'nota_id': nota_id}
