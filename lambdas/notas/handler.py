import json
import os
import base64
from datetime import datetime
import sys
sys.path.insert(0, '/opt/python')
import boto3
from shared.db import get_connection
from shared.response import success, error

sqs = boto3.client('sqs')
s3 = boto3.client('s3')
ses = boto3.client('ses')

QUEUE_URL = os.environ['SQS_QUEUE_URL']
BUCKET = os.environ['S3_BUCKET']
API_BASE_URL = os.environ['API_BASE_URL']
SES_SENDER = os.environ['SES_SENDER']


def handler(event, context):
    method = event['httpMethod']
    path_params = event.get('pathParameters') or {}
    nota_id = path_params.get('id')
    resource = event.get('resource', '')

    if method == 'POST' and not nota_id:
        return crear_nota(event)
    elif method == 'GET' and nota_id and resource.endswith('/pdf'):
        return descargar_pdf(nota_id)
    elif method == 'GET' and nota_id:
        return leer_nota(nota_id)
    elif method == 'POST' and nota_id and resource.endswith('/enviar'):
        return reenviar_nota(nota_id)
    return error('Metodo no soportado', 405)


def crear_nota(event):
    body = json.loads(event['body'])
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            folio = 'NV-' + datetime.now().strftime('%Y%m%d%H%M%S')
            detalle = body['detalle']
            total = sum(item['cantidad'] * item['precio_unitario'] for item in detalle)

            cur.execute(
                "INSERT INTO notas_venta (folio, cliente_id, dir_facturacion_id, dir_envio_id, total) VALUES (%s,%s,%s,%s,%s)",
                (folio, body['cliente_id'], body['dir_facturacion_id'], body['dir_envio_id'], total)
            )
            nota_id = cur.lastrowid

            for item in detalle:
                importe = item['cantidad'] * item['precio_unitario']
                cur.execute(
                    "INSERT INTO notas_venta_detalle (nota_id, producto_id, cantidad, precio_unitario, importe) VALUES (%s,%s,%s,%s,%s)",
                    (nota_id, item['producto_id'], item['cantidad'], item['precio_unitario'], importe)
                )
            conn.commit()

            sqs.send_message(
                QueueUrl=QUEUE_URL,
                MessageBody=json.dumps({'nota_id': nota_id})
            )

            return success({'id': nota_id, 'folio': folio, 'total': total}, 201)
    finally:
        conn.close()


def leer_nota(nota_id):
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT nv.*, c.razon_social, c.nombre_comercial, c.rfc, c.email, c.telefono
                FROM notas_venta nv
                JOIN clientes c ON nv.cliente_id = c.id
                WHERE nv.id = %s
            """, (nota_id,))
            nota = cur.fetchone()
            if not nota:
                return error('Nota no encontrada', 404)

            cur.execute("""
                SELECT nvd.*, p.nombre as producto_nombre
                FROM notas_venta_detalle nvd
                JOIN productos p ON nvd.producto_id = p.id
                WHERE nvd.nota_id = %s
            """, (nota_id,))
            nota['detalle'] = cur.fetchall()

            cur.execute("SELECT * FROM domicilios WHERE id=%s", (nota['dir_facturacion_id'],))
            nota['dir_facturacion'] = cur.fetchone()
            cur.execute("SELECT * FROM domicilios WHERE id=%s", (nota['dir_envio_id'],))
            nota['dir_envio'] = cur.fetchone()

            return success(nota)
    finally:
        conn.close()


def descargar_pdf(nota_id):
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT nv.folio, c.rfc FROM notas_venta nv
                JOIN clientes c ON nv.cliente_id = c.id
                WHERE nv.id = %s
            """, (nota_id,))
            nota = cur.fetchone()
            if not nota:
                return error('Nota no encontrada', 404)

        s3_key = f"{nota['rfc']}/{nota['folio']}.pdf"

        obj = s3.get_object(Bucket=BUCKET, Key=s3_key)
        pdf_content = obj['Body'].read()

        # Actualizar metadato nota-descargada a true
        s3.copy_object(
            Bucket=BUCKET,
            CopySource={'Bucket': BUCKET, 'Key': s3_key},
            Key=s3_key,
            Metadata={
                'hora-envio': obj['Metadata'].get('hora-envio', ''),
                'nota-descargada': 'true',
                'veces-enviado': obj['Metadata'].get('veces-enviado', '1')
            },
            MetadataDirective='REPLACE'
        )

        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/pdf',
                'Content-Disposition': f'attachment; filename="{nota["folio"]}.pdf"'
            },
            'body': base64.b64encode(pdf_content).decode('utf-8'),
            'isBase64Encoded': True
        }
    finally:
        conn.close()


def reenviar_nota(nota_id):
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT nv.folio, c.rfc, c.email, c.nombre_comercial
                FROM notas_venta nv
                JOIN clientes c ON nv.cliente_id = c.id
                WHERE nv.id = %s
            """, (nota_id,))
            nota = cur.fetchone()
            if not nota:
                return error('Nota no encontrada', 404)

        s3_key = f"{nota['rfc']}/{nota['folio']}.pdf"
        download_url = f"{API_BASE_URL}/notas/{nota_id}/pdf"

        ses.send_email(
            Source=SES_SENDER,
            Destination={'ToAddresses': [nota['email']]},
            Message={
                'Subject': {'Data': f'Nota de Venta {nota["folio"]}'},
                'Body': {
                    'Html': {'Data': f"""
                        <h2>Nota de Venta</h2>
                        <p>Estimado {nota['nombre_comercial']},</p>
                        <p>Se ha generado su nota de venta con folio <b>{nota['folio']}</b>.</p>
                        <p><a href="{download_url}">Descargar Nota en PDF</a></p>
                    """}
                }
            }
        )

        obj = s3.head_object(Bucket=BUCKET, Key=s3_key)
        veces = int(obj['Metadata'].get('veces-enviado', '1')) + 1
        s3.copy_object(
            Bucket=BUCKET,
            CopySource={'Bucket': BUCKET, 'Key': s3_key},
            Key=s3_key,
            Metadata={
                'hora-envio': datetime.now().isoformat(),
                'nota-descargada': obj['Metadata'].get('nota-descargada', 'false'),
                'veces-enviado': str(veces)
            },
            MetadataDirective='REPLACE'
        )

        return success({'message': 'Nota reenviada', 'veces_enviado': veces})
    finally:
        conn.close()
