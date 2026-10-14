CREATE DATABASE IF NOT EXISTS examen01;
USE examen01;

CREATE TABLE IF NOT EXISTS clientes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    razon_social VARCHAR(255) NOT NULL,
    nombre_comercial VARCHAR(255) NOT NULL,
    rfc VARCHAR(13) NOT NULL,
    email VARCHAR(255) NOT NULL,
    telefono VARCHAR(20) NOT NULL
);

CREATE TABLE IF NOT EXISTS domicilios (
    id INT AUTO_INCREMENT PRIMARY KEY,
    cliente_id INT NOT NULL,
    domicilio VARCHAR(255) NOT NULL,
    colonia VARCHAR(255) NOT NULL,
    municipio VARCHAR(255) NOT NULL,
    estado VARCHAR(100) NOT NULL,
    tipo ENUM('FACTURACION', 'ENVIO') NOT NULL,
    FOREIGN KEY (cliente_id) REFERENCES clientes(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS productos (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(255) NOT NULL,
    unidad_medida VARCHAR(50) NOT NULL,
    precio_base DECIMAL(10,2) NOT NULL
);

CREATE TABLE IF NOT EXISTS notas_venta (
    id INT AUTO_INCREMENT PRIMARY KEY,
    folio VARCHAR(50) NOT NULL UNIQUE,
    cliente_id INT NOT NULL,
    dir_facturacion_id INT NOT NULL,
    dir_envio_id INT NOT NULL,
    total DECIMAL(10,2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (cliente_id) REFERENCES clientes(id),
    FOREIGN KEY (dir_facturacion_id) REFERENCES domicilios(id),
    FOREIGN KEY (dir_envio_id) REFERENCES domicilios(id)
);

CREATE TABLE IF NOT EXISTS notas_venta_detalle (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nota_id INT NOT NULL,
    producto_id INT NOT NULL,
    cantidad INT NOT NULL,
    precio_unitario DECIMAL(10,2) NOT NULL,
    importe DECIMAL(10,2) NOT NULL,
    FOREIGN KEY (nota_id) REFERENCES notas_venta(id) ON DELETE CASCADE,
    FOREIGN KEY (producto_id) REFERENCES productos(id)
);
