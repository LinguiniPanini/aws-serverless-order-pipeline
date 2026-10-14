import json
import sys
sys.path.insert(0, '/opt/python')
from shared.db import get_connection
from shared.response import success, error


def handler(event, context):
    method = event['httpMethod']
    path_params = event.get('pathParameters') or {}
    producto_id = path_params.get('id')

    if method == 'POST':
        return crear(event)
    elif method == 'GET' and producto_id:
        return obtener(producto_id)
    elif method == 'GET':
        return listar()
    elif method == 'PUT' and producto_id:
        return actualizar(producto_id, event)
    elif method == 'DELETE' and producto_id:
        return eliminar(producto_id)
    return error('Metodo no soportado', 405)


def crear(event):
    body = json.loads(event['body'])
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO productos (nombre, unidad_medida, precio_base) VALUES (%s,%s,%s)",
                (body['nombre'], body['unidad_medida'], body['precio_base'])
            )
            conn.commit()
            return success({'id': cur.lastrowid, **body}, 201)
    finally:
        conn.close()


def listar():
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM productos")
            return success(cur.fetchall())
    finally:
        conn.close()


def obtener(producto_id):
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM productos WHERE id=%s", (producto_id,))
            row = cur.fetchone()
            if not row:
                return error('Producto no encontrado', 404)
            return success(row)
    finally:
        conn.close()


def actualizar(producto_id, event):
    body = json.loads(event['body'])
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE productos SET nombre=%s, unidad_medida=%s, precio_base=%s WHERE id=%s",
                (body['nombre'], body['unidad_medida'], body['precio_base'], producto_id)
            )
            conn.commit()
            if cur.rowcount == 0:
                return error('Producto no encontrado', 404)
            return success({'id': int(producto_id), **body})
    finally:
        conn.close()


def eliminar(producto_id):
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM productos WHERE id=%s", (producto_id,))
            conn.commit()
            if cur.rowcount == 0:
                return error('Producto no encontrado', 404)
            return success({'message': 'Producto eliminado'})
    finally:
        conn.close()
