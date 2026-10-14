#!/bin/bash
# ============================================
# Tests de API - Examen 01 Notas de Venta
# ============================================
API="https://rdahf6aqhd.execute-api.us-east-1.amazonaws.com/prod"

# ============================================
# CLIENTES
# ============================================

echo "========== CLIENTES =========="

echo ">>> POST /clientes (crear)"
curl -s -X POST "$API/clientes" \
  -H "Content-Type: application/json" \
  -d '{"razon_social":"Empresa SA de CV","nombre_comercial":"Empresa","rfc":"EMP123456789","email":"luis.gonzaleze@iteso.mx","telefono":"3312345678"}'
echo -e "\n"

echo ">>> GET /clientes (listar)"
curl -s "$API/clientes"
echo -e "\n"

echo ">>> GET /clientes/1 (obtener)"
curl -s "$API/clientes/1"
echo -e "\n"

echo ">>> PUT /clientes/1 (actualizar)"
curl -s -X PUT "$API/clientes/1" \
  -H "Content-Type: application/json" \
  -d '{"razon_social":"Empresa Actualizada SA de CV","nombre_comercial":"Empresa Act","rfc":"EMP123456789","email":"luis.gonzaleze@iteso.mx","telefono":"3398765432"}'
echo -e "\n"

# ============================================
# DOMICILIOS
# ============================================

echo "========== DOMICILIOS =========="

echo ">>> POST /clientes/1/domicilios (crear facturacion)"
curl -s -X POST "$API/clientes/1/domicilios" \
  -H "Content-Type: application/json" \
  -d '{"domicilio":"Calle Reforma #100","colonia":"Centro","municipio":"Guadalajara","estado":"Jalisco","tipo":"FACTURACION"}'
echo -e "\n"

echo ">>> POST /clientes/1/domicilios (crear envio)"
curl -s -X POST "$API/clientes/1/domicilios" \
  -H "Content-Type: application/json" \
  -d '{"domicilio":"Av Patria #200","colonia":"Jardines","municipio":"Zapopan","estado":"Jalisco","tipo":"ENVIO"}'
echo -e "\n"

echo ">>> GET /clientes/1/domicilios (listar)"
curl -s "$API/clientes/1/domicilios"
echo -e "\n"

echo ">>> GET /domicilios/1 (obtener)"
curl -s "$API/domicilios/1"
echo -e "\n"

echo ">>> PUT /domicilios/1 (actualizar)"
curl -s -X PUT "$API/domicilios/1" \
  -H "Content-Type: application/json" \
  -d '{"domicilio":"Calle Reforma #150","colonia":"Centro Historico","municipio":"Guadalajara","estado":"Jalisco","tipo":"FACTURACION"}'
echo -e "\n"

# ============================================
# PRODUCTOS
# ============================================

echo "========== PRODUCTOS =========="

echo ">>> POST /productos (crear 1)"
curl -s -X POST "$API/productos" \
  -H "Content-Type: application/json" \
  -d '{"nombre":"Laptop HP Pavilion","unidad_medida":"pieza","precio_base":15000.00}'
echo -e "\n"

echo ">>> POST /productos (crear 2)"
curl -s -X POST "$API/productos" \
  -H "Content-Type: application/json" \
  -d '{"nombre":"Mouse Logitech","unidad_medida":"pieza","precio_base":450.00}'
echo -e "\n"

echo ">>> POST /productos (crear 3)"
curl -s -X POST "$API/productos" \
  -H "Content-Type: application/json" \
  -d '{"nombre":"Cable HDMI 2m","unidad_medida":"pieza","precio_base":120.00}'
echo -e "\n"

echo ">>> GET /productos (listar)"
curl -s "$API/productos"
echo -e "\n"

echo ">>> GET /productos/1 (obtener)"
curl -s "$API/productos/1"
echo -e "\n"

echo ">>> PUT /productos/1 (actualizar)"
curl -s -X PUT "$API/productos/1" \
  -H "Content-Type: application/json" \
  -d '{"nombre":"Laptop HP Pavilion 15","unidad_medida":"pieza","precio_base":16500.00}'
echo -e "\n"

# ============================================
# NOTAS DE VENTA
# ============================================

echo "========== NOTAS DE VENTA =========="

echo ">>> POST /notas (crear nota con 3 productos)"
curl -s -X POST "$API/notas" \
  -H "Content-Type: application/json" \
  -d '{
    "cliente_id": 1,
    "dir_facturacion_id": 1,
    "dir_envio_id": 2,
    "detalle": [
      {"producto_id": 1, "cantidad": 2, "precio_unitario": 16500.00},
      {"producto_id": 2, "cantidad": 5, "precio_unitario": 450.00},
      {"producto_id": 3, "cantidad": 10, "precio_unitario": 120.00}
    ]
  }'
echo -e "\n"

echo "Esperando 10s a que Step Function procese (PDF + S3 + Email)..."
sleep 10

echo ">>> GET /notas/1 (leer JSON - NO afecta metadatos)"
curl -s "$API/notas/1"
echo -e "\n"

echo ">>> GET /notas/1/pdf (descargar PDF - SI actualiza nota-descargada=true)"
curl -s -o nota_descargada.pdf "$API/notas/1/pdf"
echo "PDF guardado en nota_descargada.pdf ($(wc -c < nota_descargada.pdf) bytes)"
echo ""

echo ">>> POST /notas/1/enviar (reenviar nota - incrementa veces-enviado)"
curl -s -X POST "$API/notas/1/enviar"
echo -e "\n"

# ============================================
# VERIFICAR METADATOS S3
# ============================================

echo "========== METADATOS S3 =========="
echo ">>> Verificando metadatos del PDF en S3..."
aws s3api head-object \
  --bucket 745741-esi3898k-examen1 \
  --key "EMP123456789/$(curl -s "$API/notas/1" | python3 -c "import sys,json; print(json.load(sys.stdin)['folio'])").pdf" \
  --query 'Metadata' --output json --region us-east-1
echo ""

# ============================================
# DELETE (limpiar datos de prueba)
# Descomenta si quieres borrar todo
# ============================================

# echo "========== CLEANUP =========="
# echo ">>> DELETE /productos/3"
# curl -s -X DELETE "$API/productos/3"
# echo ""
# echo ">>> DELETE /domicilios/2"
# curl -s -X DELETE "$API/domicilios/2"
# echo ""
# echo ">>> DELETE /clientes/1 (cascade domicilios)"
# curl -s -X DELETE "$API/clientes/1"
# echo ""

echo "========== TESTS COMPLETADOS =========="
