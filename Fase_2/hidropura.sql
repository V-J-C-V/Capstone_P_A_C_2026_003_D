CREATE TABLE usuario (
    id_usuario SERIAL PRIMARY KEY,
    rut VARCHAR(12) UNIQUE NOT NULL,
    nombre_completo VARCHAR(150) NOT NULL,
    correo VARCHAR(150) UNIQUE NOT NULL,
    contrasena VARCHAR(255) NOT NULL,
    telefono VARCHAR(20),
    rol_usuario VARCHAR(50) NOT NULL,
    estado_activo BOOLEAN DEFAULT TRUE
);

CREATE TABLE producto (
    id_producto SERIAL PRIMARY KEY,
    nombre_producto VARCHAR(150) NOT NULL,
    descripcion TEXT,
    precio_unitario INTEGER NOT NULL,
    stock_disponible INTEGER NOT NULL,
    estado_activo BOOLEAN DEFAULT TRUE
);

CREATE TABLE cita_servicio (
    id_cita SERIAL PRIMARY KEY,
    id_usuario_cliente INTEGER NOT NULL REFERENCES usuario(id_usuario),
    id_usuario_trabajador INTEGER REFERENCES usuario(id_usuario),
    direccion_instalacion VARCHAR(255) NOT NULL,
    fecha_hora_reserva TIMESTAMP NOT NULL,
    tipo_servicio VARCHAR(100) NOT NULL,
    estado_cita VARCHAR(50) NOT NULL
);

CREATE TABLE pedido (
    id_pedido SERIAL PRIMARY KEY,
    id_usuario INTEGER NOT NULL REFERENCES usuario(id_usuario),
    direccion_despacho VARCHAR(255),
    fecha_pedido TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    monto_total INTEGER NOT NULL,
    estado_pedido VARCHAR(50) NOT NULL
);

CREATE TABLE detalle_pedido (
    id_detalle SERIAL PRIMARY KEY,
    id_pedido INTEGER NOT NULL REFERENCES pedido(id_pedido) ON DELETE CASCADE,
    id_producto INTEGER NOT NULL REFERENCES producto(id_producto),
    cantidad INTEGER NOT NULL,
    precio_unitario_historico INTEGER NOT NULL,
    precio_subtotal INTEGER NOT NULL
);

CREATE TABLE transaccion_pago (
    id_transaccion SERIAL PRIMARY KEY,
    id_pedido INTEGER REFERENCES pedido(id_pedido),
    id_cita INTEGER REFERENCES cita_servicio(id_cita),
    codigo_mercadopago VARCHAR(255) UNIQUE,
    fecha_pago TIMESTAMP,
    estado_pago VARCHAR(50) NOT NULL
);