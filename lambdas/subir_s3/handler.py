import base64
import os
from datetime import datetime
import boto3

s3 = boto3.client('s3')
BUCKET = os.environ['S3_BUCKET']


def handler(event, context):
    pdf_bytes = base64.b64decode(event['pdf_base64'])
    rfc = event['rfc']
    folio = event['folio']
    s3_key = f"{rfc}/{folio}.pdf"

    s3.put_object(
        Bucket=BUCKET,
        Key=s3_key,
        Body=pdf_bytes,
        ContentType='application/pdf',
        Metadata={
            'hora-envio': datetime.now().isoformat(),
            'nota-descargada': 'false',
            'veces-enviado': '1'
        }
    )

    return {
        'nota_id': event['nota_id'],
        'folio': folio,
        'rfc': rfc,
        'email': event['email'],
        'nombre_comercial': event['nombre_comercial'],
        's3_key': s3_key
    }
