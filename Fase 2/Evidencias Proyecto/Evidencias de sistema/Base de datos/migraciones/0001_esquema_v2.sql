-- =============================================================================
-- HidroPura System - Base de datos v2 (PostgreSQL 16)
-- Construida sobre hidropura.sql (v1). Los cambios y el requisito que los
-- exige están en CAMBIOS_BD_v2.md.
-- Convenciones: fechas en TIMESTAMPTZ, montos en pesos (INTEGER) y estados en
-- minúsculas con CHECK.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Usuarios y roles
-- -----------------------------------------------------------------------------
CREATE TABLE usuario (
    id_usuario SERIAL PRIMARY KEY,
    rut VARCHAR(12) UNIQUE NOT NULL
        CHECK (rut ~ '^[0-9]{7,8}-[0-9K]$'),          -- sin puntos y con guion: 12345678-K
    nombre_completo VARCHAR(150) NOT NULL,
    correo VARCHAR(150) NOT NULL,                     -- único sin importar mayúsculas (índice abajo)
    contrasena_hash VARCHAR(255) NOT NULL,            -- hash bcrypt/argon2, nunca la contraseña
    telefono VARCHAR(20),
    rol_usuario VARCHAR(20) NOT NULL DEFAULT 'cliente'
        CHECK (rol_usuario IN ('administrador', 'trabajador', 'cliente')),
    estado_activo BOOLEAN NOT NULL DEFAULT TRUE,
    -- Recuperación de contraseña: se guarda el hash del token, no el token
    token_recuperacion_hash VARCHAR(255),
    token_recuperacion_expira TIMESTAMPTZ,
    -- Consentimiento (Ley 21.719)
    acepta_politica BOOLEAN NOT NULL DEFAULT FALSE,
    fecha_aceptacion_politica TIMESTAMPTZ,
    acepta_marketing BOOLEAN NOT NULL DEFAULT FALSE,
    fecha_creacion TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (NOT acepta_politica OR fecha_aceptacion_politica IS NOT NULL)
);

CREATE UNIQUE INDEX usuario_correo_unico ON usuario (lower(correo));

-- -----------------------------------------------------------------------------
-- Catálogo
-- -----------------------------------------------------------------------------
CREATE TABLE producto (
    id_producto SERIAL PRIMARY KEY,
    nombre_producto VARCHAR(150) NOT NULL,
    descripcion TEXT,
    tipo VARCHAR(20) NOT NULL
        CHECK (tipo IN ('equipo', 'insumo', 'repuesto')),
    marca VARCHAR(80),
    imagen_url VARCHAR(500),
    precio_unitario INTEGER NOT NULL CHECK (precio_unitario >= 0),
    stock_disponible INTEGER NOT NULL CHECK (stock_disponible >= 0),
    estado_activo BOOLEAN NOT NULL DEFAULT TRUE,     -- FALSE = oculto del catálogo (REQ-03)
    fecha_creacion TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE servicio (
    id_servicio SERIAL PRIMARY KEY,
    nombre VARCHAR(100) UNIQUE NOT NULL,
    descripcion TEXT,
    precio INTEGER NOT NULL CHECK (precio >= 0),     -- 0 = gratis, se confirma sin pago
    estado_activo BOOLEAN NOT NULL DEFAULT TRUE,
    fecha_creacion TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- Disponibilidad del calendario (bloques fijos, un solo equipo)
-- -----------------------------------------------------------------------------
CREATE TABLE horario_atencion (
    id_horario SERIAL PRIMARY KEY,
    dia_semana SMALLINT NOT NULL CHECK (dia_semana BETWEEN 1 AND 7),  -- ISO: 1 = lunes, 7 = domingo
    hora_inicio TIME NOT NULL,
    hora_fin TIME NOT NULL,
    estado_activo BOOLEAN NOT NULL DEFAULT TRUE,
    fecha_creacion TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (dia_semana, hora_inicio),
    CHECK (hora_fin > hora_inicio)
);

CREATE TABLE fecha_bloqueada (
    fecha DATE PRIMARY KEY,
    motivo VARCHAR(200),
    fecha_creacion TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- Citas
-- -----------------------------------------------------------------------------
CREATE TABLE cita_servicio (
    id_cita SERIAL PRIMARY KEY,
    id_usuario_cliente INTEGER NOT NULL REFERENCES usuario(id_usuario),
    id_usuario_trabajador INTEGER REFERENCES usuario(id_usuario),  -- se asigna después
    id_servicio INTEGER NOT NULL REFERENCES servicio(id_servicio),
    direccion_instalacion VARCHAR(255) NOT NULL,
    comuna VARCHAR(80) NOT NULL,
    fecha_hora_reserva TIMESTAMPTZ NOT NULL,          -- inicio del bloque
    monto INTEGER NOT NULL CHECK (monto >= 0),        -- precio del servicio al reservar
    estado_cita VARCHAR(20) NOT NULL
        CHECK (estado_cita IN ('retenida', 'confirmada', 'realizada', 'cancelada', 'expirada')),
    retenida_hasta TIMESTAMPTZ,                       -- vencimiento de la retención mientras se paga
    fecha_creacion TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (estado_cita <> 'retenida' OR retenida_hasta IS NOT NULL)
);

-- Anti-overbooking (HU-05): una hora solo puede estar tomada por una cita viva.
-- La base rechaza la segunda aunque las dos lleguen al mismo tiempo.
CREATE UNIQUE INDEX cita_hora_ocupada ON cita_servicio (fecha_hora_reserva)
    WHERE estado_cita IN ('retenida', 'confirmada', 'realizada');

CREATE INDEX cita_fecha_hora ON cita_servicio (fecha_hora_reserva);
CREATE INDEX cita_cliente ON cita_servicio (id_usuario_cliente);
CREATE INDEX cita_trabajador ON cita_servicio (id_usuario_trabajador);
CREATE INDEX cita_servicio_fk ON cita_servicio (id_servicio);

-- -----------------------------------------------------------------------------
-- Pedidos
-- -----------------------------------------------------------------------------
CREATE TABLE pedido (
    id_pedido SERIAL PRIMARY KEY,
    id_usuario INTEGER NOT NULL REFERENCES usuario(id_usuario),
    direccion_despacho VARCHAR(255),
    comuna_despacho VARCHAR(80),
    fecha_pedido TIMESTAMPTZ NOT NULL DEFAULT now(),
    monto_total INTEGER NOT NULL CHECK (monto_total >= 0),
    estado_pedido VARCHAR(20) NOT NULL DEFAULT 'pendiente_pago'
        CHECK (estado_pedido IN ('pendiente_pago', 'pagado', 'despachado', 'entregado', 'cancelado'))
);

CREATE INDEX pedido_usuario ON pedido (id_usuario);

CREATE TABLE detalle_pedido (
    id_detalle SERIAL PRIMARY KEY,
    id_pedido INTEGER NOT NULL REFERENCES pedido(id_pedido) ON DELETE CASCADE,
    id_producto INTEGER NOT NULL REFERENCES producto(id_producto),
    cantidad INTEGER NOT NULL CHECK (cantidad > 0),
    precio_unitario_historico INTEGER NOT NULL CHECK (precio_unitario_historico >= 0),
    precio_subtotal INTEGER NOT NULL,
    UNIQUE (id_pedido, id_producto),
    CHECK (precio_subtotal = cantidad * precio_unitario_historico)
);

CREATE INDEX detalle_producto ON detalle_pedido (id_producto);

-- -----------------------------------------------------------------------------
-- Pagos (Mercado Pago). Un pedido o una cita puede tener varios intentos.
-- -----------------------------------------------------------------------------
CREATE TABLE transaccion_pago (
    id_transaccion SERIAL PRIMARY KEY,
    id_pedido INTEGER REFERENCES pedido(id_pedido),
    id_cita INTEGER REFERENCES cita_servicio(id_cita),
    preference_id VARCHAR(255),                       -- preferencia de Checkout Pro
    codigo_mercadopago VARCHAR(255) UNIQUE,           -- id del pago; evita registrar dos veces un webhook
    monto INTEGER NOT NULL CHECK (monto > 0),
    estado_pago VARCHAR(20) NOT NULL DEFAULT 'pendiente'
        CHECK (estado_pago IN ('pendiente', 'aprobado', 'rechazado', 'cancelado', 'reembolsado')),
    fecha_pago TIMESTAMPTZ,
    fecha_creacion TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (num_nonnulls(id_pedido, id_cita) = 1)     -- de un pedido o de una cita, nunca ambos ni ninguno
);

CREATE INDEX transaccion_pedido ON transaccion_pago (id_pedido);
CREATE INDEX transaccion_cita ON transaccion_pago (id_cita);

-- -----------------------------------------------------------------------------
-- Cotizaciones especiales (REQ-06)
-- -----------------------------------------------------------------------------
CREATE TABLE cotizacion (
    id_cotizacion SERIAL PRIMARY KEY,
    id_usuario INTEGER REFERENCES usuario(id_usuario),  -- si la pidió con sesión iniciada
    nombre VARCHAR(150) NOT NULL,
    correo VARCHAR(150) NOT NULL,
    telefono VARCHAR(20) NOT NULL,
    comuna VARCHAR(80),
    detalle TEXT NOT NULL,
    estado VARCHAR(20) NOT NULL DEFAULT 'nueva'
        CHECK (estado IN ('nueva', 'respondida', 'cerrada')),
    acepta_politica BOOLEAN NOT NULL CHECK (acepta_politica),  -- sin consentimiento no se guarda
    fecha_creacion TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX cotizacion_usuario ON cotizacion (id_usuario);

-- =============================================================================
-- Funciones de agenda. Las horas se interpretan en hora de Chile.
-- Errores propios: HP001 = hora no disponible, HP002 = hora o servicio inválido.
-- =============================================================================

-- REQ-04: bloques libres de un día.
CREATE FUNCTION horas_disponibles(p_fecha DATE)
RETURNS TABLE (fecha_hora TIMESTAMPTZ, hora_fin TIMESTAMPTZ)
LANGUAGE sql STABLE AS $$
    SELECT (p_fecha + h.hora_inicio) AT TIME ZONE 'America/Santiago',
           (p_fecha + h.hora_fin) AT TIME ZONE 'America/Santiago'
    FROM horario_atencion h
    WHERE h.estado_activo
      AND h.dia_semana = EXTRACT(ISODOW FROM p_fecha)
      AND NOT EXISTS (SELECT 1 FROM fecha_bloqueada b WHERE b.fecha = p_fecha)
      AND (p_fecha + h.hora_inicio) AT TIME ZONE 'America/Santiago' > now()
      AND NOT EXISTS (
          SELECT 1 FROM cita_servicio c
          WHERE c.fecha_hora_reserva = (p_fecha + h.hora_inicio) AT TIME ZONE 'America/Santiago'
            AND (c.estado_cita IN ('confirmada', 'realizada')
                 OR (c.estado_cita = 'retenida' AND c.retenida_hasta > now())))
    ORDER BY 1;
$$;

-- REQ-05: toma una hora. Si el servicio cuesta, la deja retenida mientras se
-- paga; si es gratis, la confirma. Devuelve el id de la cita.
CREATE FUNCTION tomar_hora(
    p_cliente INTEGER,
    p_servicio INTEGER,
    p_fecha_hora TIMESTAMPTZ,
    p_direccion VARCHAR,
    p_comuna VARCHAR,
    p_minutos INTEGER DEFAULT 15
) RETURNS INTEGER
LANGUAGE plpgsql AS $$
DECLARE
    v_local TIMESTAMP := p_fecha_hora AT TIME ZONE 'America/Santiago';
    v_precio INTEGER;
    v_id INTEGER;
BEGIN
    IF p_fecha_hora <= now() THEN
        RAISE EXCEPTION 'La hora ya pasó' USING ERRCODE = 'HP002';
    END IF;

    SELECT precio INTO v_precio FROM servicio WHERE id_servicio = p_servicio AND estado_activo;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El servicio no existe o no está activo' USING ERRCODE = 'HP002';
    END IF;

    IF EXISTS (SELECT 1 FROM fecha_bloqueada WHERE fecha = v_local::date) THEN
        RAISE EXCEPTION 'La fecha % está bloqueada', v_local::date USING ERRCODE = 'HP002';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM horario_atencion
        WHERE estado_activo
          AND dia_semana = EXTRACT(ISODOW FROM v_local)
          AND hora_inicio = v_local::time
    ) THEN
        RAISE EXCEPTION 'El horario % no corresponde a un bloque de atención', v_local USING ERRCODE = 'HP002';
    END IF;

    -- Libera las retenciones vencidas de esta hora (no hace falta un cron).
    UPDATE cita_servicio SET estado_cita = 'expirada'
    WHERE fecha_hora_reserva = p_fecha_hora
      AND estado_cita = 'retenida'
      AND retenida_hasta <= now();

    BEGIN
        INSERT INTO cita_servicio (id_usuario_cliente, id_servicio, direccion_instalacion, comuna,
                                   fecha_hora_reserva, monto, estado_cita, retenida_hasta)
        VALUES (p_cliente, p_servicio, p_direccion, p_comuna, p_fecha_hora, v_precio,
                CASE WHEN v_precio = 0 THEN 'confirmada' ELSE 'retenida' END,
                CASE WHEN v_precio = 0 THEN NULL ELSE now() + make_interval(mins => p_minutos) END)
        RETURNING id_cita INTO v_id;
    EXCEPTION WHEN unique_violation THEN
        RAISE EXCEPTION 'Hora no disponible' USING ERRCODE = 'HP001';
    END;

    RETURN v_id;
END;
$$;

-- =============================================================================
-- Vistas para Power BI (REQ-08). Los meses se agrupan en hora de Chile.
-- =============================================================================

-- Ventas de productos, por mes de compra.
CREATE VIEW v_ventas_productos_mensual AS
SELECT date_trunc('month', p.fecha_pedido AT TIME ZONE 'America/Santiago')::date AS mes,
       count(DISTINCT p.id_pedido) AS pedidos,
       sum(d.cantidad) AS unidades,
       sum(d.precio_subtotal) AS monto
FROM pedido p
JOIN detalle_pedido d ON d.id_pedido = p.id_pedido
WHERE p.estado_pedido IN ('pagado', 'despachado', 'entregado')
GROUP BY 1;

-- Ingresos por servicios, por mes en que se reservó (se vendió).
CREATE VIEW v_ingresos_servicios_mensual AS
SELECT date_trunc('month', c.fecha_creacion AT TIME ZONE 'America/Santiago')::date AS mes,
       s.nombre AS servicio,
       count(*) AS citas,
       sum(c.monto) AS monto
FROM cita_servicio c
JOIN servicio s ON s.id_servicio = c.id_servicio
WHERE c.estado_cita IN ('confirmada', 'realizada')
GROUP BY 1, 2;

-- Carga de trabajo: citas por mes de atención y estado.
CREATE VIEW v_citas_por_estado AS
SELECT date_trunc('month', c.fecha_hora_reserva AT TIME ZONE 'America/Santiago')::date AS mes,
       c.estado_cita AS estado,
       count(*) AS citas
FROM cita_servicio c
GROUP BY 1, 2;

CREATE VIEW v_productos_mas_vendidos AS
SELECT pr.id_producto,
       pr.nombre_producto AS producto,
       pr.tipo,
       pr.marca,
       sum(d.cantidad) AS unidades,
       sum(d.precio_subtotal) AS monto
FROM detalle_pedido d
JOIN pedido p ON p.id_pedido = d.id_pedido
JOIN producto pr ON pr.id_producto = d.id_producto
WHERE p.estado_pedido IN ('pagado', 'despachado', 'entregado')
GROUP BY pr.id_producto, pr.nombre_producto, pr.tipo, pr.marca;

CREATE VIEW v_cotizaciones_mensual AS
SELECT date_trunc('month', fecha_creacion AT TIME ZONE 'America/Santiago')::date AS mes,
       estado,
       count(*) AS cotizaciones
FROM cotizacion
GROUP BY 1, 2;
