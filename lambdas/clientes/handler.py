import json
import sys
sys.path.insert(0, '/opt/python')
from shared.db import get_connection
from shared.response import success, error


def handler(event, context):
    method = event['httpMethod']
    path_params = event.get('pathParameters') or {}
    cliente_id = path_params.get('id')

    if method == 'POST':
        return crear(event)
    elif method == 'GET' and cliente_id:
        return obtener(cliente_id)
    elif method == 'GET':
        return listar()
    elif method == 'PUT' and cliente_id:
        return actualizar(cliente_id, event)
    elif method == 'DELETE' and cliente_id:
        return eliminar(cliente_id)
    return error('Metodo no soportado', 405)


def crear(event):
    body = json.loads(event['body'])
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO clientes (razon_social, nombre_comercial, rfc, email, telefono) VALUES (%s,%s,%s,%s,%s)",
                (body['razon_social'], body['nombre_comercial'], body['rfc'], body['email'], body['telefono'])
            )
            conn.commit()
            return success({'id': cur.lastrowid, **body}, 201)
    finally:
        conn.close()


def listar():
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM clientes")
            return success(cur.fetchall())
    finally:
        conn.close()


def obtener(cliente_id):
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM clientes WHERE id=%s", (cliente_id,))
            row = cur.fetchone()
            if not row:
                return error('Cliente no encontrado', 404)
            return success(row)
    finally:
        conn.close()


def actualizar(cliente_id, event):
    body = json.loads(event['body'])
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE clientes SET razon_social=%s, nombre_comercial=%s, rfc=%s, email=%s, telefono=%s WHERE id=%s",
                (body['razon_social'], body['nombre_comercial'], body['rfc'], body['email'], body['telefono'], cliente_id)
            )
            conn.commit()
            if cur.rowcount == 0:
                return error('Cliente no encontrado', 404)
            return success({'id': int(cliente_id), **body})
    finally:
        conn.close()


def eliminar(cliente_id):
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM clientes WHERE id=%s", (cliente_id,))
            conn.commit()
            if cur.rowcount == 0:
                return error('Cliente no encontrado', 404)
            return success({'message': 'Cliente eliminado'})
    finally:
        conn.close()
