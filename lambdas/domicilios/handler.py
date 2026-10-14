import json
import sys
sys.path.insert(0, '/opt/python')
from shared.db import get_connection
from shared.response import success, error


def handler(event, context):
    method = event['httpMethod']
    path_params = event.get('pathParameters') or {}
    domicilio_id = path_params.get('domicilioId')
    cliente_id = path_params.get('id')

    if method == 'POST' and cliente_id:
        return crear(cliente_id, event)
    elif method == 'GET' and cliente_id and not domicilio_id:
        return listar(cliente_id)
    elif method == 'GET' and domicilio_id:
        return obtener(domicilio_id)
    elif method == 'PUT' and domicilio_id:
        return actualizar(domicilio_id, event)
    elif method == 'DELETE' and domicilio_id:
        return eliminar(domicilio_id)
    return error('Metodo no soportado', 405)


def crear(cliente_id, event):
    body = json.loads(event['body'])
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO domicilios (cliente_id, domicilio, colonia, municipio, estado, tipo) VALUES (%s,%s,%s,%s,%s,%s)",
                (cliente_id, body['domicilio'], body['colonia'], body['municipio'], body['estado'], body['tipo'])
            )
            conn.commit()
            return success({'id': cur.lastrowid, 'cliente_id': int(cliente_id), **body}, 201)
    finally:
        conn.close()


def listar(cliente_id):
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM domicilios WHERE cliente_id=%s", (cliente_id,))
            return success(cur.fetchall())
    finally:
        conn.close()


def obtener(domicilio_id):
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM domicilios WHERE id=%s", (domicilio_id,))
            row = cur.fetchone()
            if not row:
                return error('Domicilio no encontrado', 404)
            return success(row)
    finally:
        conn.close()


def actualizar(domicilio_id, event):
    body = json.loads(event['body'])
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE domicilios SET domicilio=%s, colonia=%s, municipio=%s, estado=%s, tipo=%s WHERE id=%s",
                (body['domicilio'], body['colonia'], body['municipio'], body['estado'], body['tipo'], domicilio_id)
            )
            conn.commit()
            if cur.rowcount == 0:
                return error('Domicilio no encontrado', 404)
            return success({'id': int(domicilio_id), **body})
    finally:
        conn.close()


def eliminar(domicilio_id):
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM domicilios WHERE id=%s", (domicilio_id,))
            conn.commit()
            if cur.rowcount == 0:
                return error('Domicilio no encontrado', 404)
            return success({'message': 'Domicilio eliminado'})
    finally:
        conn.close()
