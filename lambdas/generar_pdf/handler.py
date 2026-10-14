import base64
import sys
sys.path.insert(0, '/opt/python')
from fpdf import FPDF
from shared.db import get_connection


def handler(event, context):
    nota_id = event['nota_id']
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

            cur.execute("""
                SELECT nvd.*, p.nombre as producto_nombre
                FROM notas_venta_detalle nvd
                JOIN productos p ON nvd.producto_id = p.id
                WHERE nvd.nota_id = %s
            """, (nota_id,))
            detalle = cur.fetchall()

        pdf = FPDF()
        pdf.add_page()

        pdf.set_font('Helvetica', 'B', 16)
        pdf.cell(0, 10, 'Nota de Venta', ln=True, align='C')
        pdf.ln(5)

        pdf.set_font('Helvetica', 'B', 12)
        pdf.cell(0, 8, 'Datos del Cliente', ln=True)
        pdf.set_font('Helvetica', '', 10)
        pdf.cell(0, 6, f"Razon Social: {nota['razon_social']}", ln=True)
        pdf.cell(0, 6, f"Nombre Comercial: {nota['nombre_comercial']}", ln=True)
        pdf.cell(0, 6, f"RFC: {nota['rfc']}", ln=True)
        pdf.cell(0, 6, f"Email: {nota['email']}", ln=True)
        pdf.cell(0, 6, f"Telefono: {nota['telefono']}", ln=True)
        pdf.ln(5)

        pdf.set_font('Helvetica', 'B', 12)
        pdf.cell(0, 8, f"Folio: {nota['folio']}", ln=True)
        pdf.ln(5)

        pdf.set_font('Helvetica', 'B', 10)
        pdf.cell(20, 8, 'Cant.', 1)
        pdf.cell(70, 8, 'Producto', 1)
        pdf.cell(40, 8, 'P. Unitario', 1)
        pdf.cell(40, 8, 'Importe', 1)
        pdf.ln()

        pdf.set_font('Helvetica', '', 10)
        for item in detalle:
            pdf.cell(20, 8, str(item['cantidad']), 1)
            pdf.cell(70, 8, item['producto_nombre'], 1)
            pdf.cell(40, 8, f"${float(item['precio_unitario']):.2f}", 1)
            pdf.cell(40, 8, f"${float(item['importe']):.2f}", 1)
            pdf.ln()

        pdf.set_font('Helvetica', 'B', 12)
        pdf.cell(130, 10, '', 0)
        pdf.cell(40, 10, f"Total: ${float(nota['total']):.2f}", 0)

        pdf_bytes = pdf.output()
        pdf_base64 = base64.b64encode(pdf_bytes).decode('utf-8')

        return {
            'nota_id': nota_id,
            'folio': nota['folio'],
            'rfc': nota['rfc'],
            'email': nota['email'],
            'nombre_comercial': nota['nombre_comercial'],
            'pdf_base64': pdf_base64
        }
    finally:
        conn.close()
