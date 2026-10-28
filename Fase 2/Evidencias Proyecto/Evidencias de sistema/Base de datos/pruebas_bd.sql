-- =============================================================================
-- HidroPura System - Pruebas de la base de datos v2
-- Requiere hidropura_v2.sql y hidropura_v2_datos.sql cargados.
-- Correr con: psql -v ON_ERROR_STOP=1 -f hidropura_v2_pruebas.sql
-- Todo ocurre dentro de una transacción que se deshace al final: no deja datos.
-- Cada caso imprime una línea "OK"; el primer caso que falla detiene el script.
-- =============================================================================

\pset tuples_only on
\pset format unaligned

BEGIN;
SET TIME ZONE 'America/Santiago';

-- -----------------------------------------------------------------------------
-- Ayudantes (temporales, desaparecen al cerrar la sesión)
-- -----------------------------------------------------------------------------

-- Ejecuta p_sql y exige que falle con el SQLSTATE p_estado.
CREATE FUNCTION pg_temp.espera_error(p_sql TEXT, p_estado TEXT, p_caso TEXT) RETURNS TEXT
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE p_sql;
    RAISE EXCEPTION 'no hubo error';
EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = p_estado THEN
        RETURN 'OK  ' || p_caso;
    ELSE
        RAISE EXCEPTION 'FALLA %: se esperaba el error %, llegó % (%)', p_caso, p_estado, SQLSTATE, SQLERRM;
    END IF;
END;
$$;

CREATE FUNCTION pg_temp.verifica(p_condicion BOOLEAN, p_caso TEXT) RETURNS TEXT
LANGUAGE plpgsql AS $$
BEGIN
    IF p_condicion IS NOT TRUE THEN
        RAISE EXCEPTION 'FALLA %', p_caso;
    END IF;
    RETURN 'OK  ' || p_caso;
END;
$$;

-- Próximo viernes (entre 1 y 7 días desde hoy), para que las pruebas no envejezcan.
CREATE FUNCTION pg_temp.viernes() RETURNS DATE
LANGUAGE sql AS $$
    SELECT current_date + ((4 - EXTRACT(ISODOW FROM current_date)::INT + 7) % 7) + 1;
$$;

CREATE FUNCTION pg_temp.hora(p_fecha DATE, p_hora TIME) RETURNS TIMESTAMPTZ
LANGUAGE sql AS $$
    SELECT (p_fecha + p_hora) AT TIME ZONE 'America/Santiago';
$$;

CREATE FUNCTION pg_temp.servicio(p_nombre TEXT) RETURNS INTEGER
LANGUAGE sql AS $$
    SELECT id_servicio FROM servicio WHERE nombre = p_nombre;
$$;

CREATE FUNCTION pg_temp.usuario(p_rut TEXT) RETURNS INTEGER
LANGUAGE sql AS $$
    SELECT id_usuario FROM usuario WHERE rut = p_rut;
$$;

-- -----------------------------------------------------------------------------
-- Datos de prueba
-- -----------------------------------------------------------------------------
INSERT INTO usuario (rut, nombre_completo, correo, contrasena_hash, rol_usuario, acepta_politica, fecha_aceptacion_politica) VALUES
('11111111-1', 'Cliente Uno', 'uno@prueba.cl', 'hash', 'cliente', TRUE, now()),
('22222222-2', 'Cliente Dos', 'dos@prueba.cl', 'hash', 'cliente', TRUE, now()),
('33333333-3', 'Instalador', 'instalador@prueba.cl', 'hash', 'trabajador', FALSE, NULL);

-- Horario propio de las pruebas, para no depender de los datos de ejemplo:
-- solo viernes, cuatro bloques de 2 horas.
DELETE FROM horario_atencion;
INSERT INTO horario_atencion (dia_semana, hora_inicio, hora_fin) VALUES
(5, '09:00', '11:00'), (5, '11:00', '13:00'), (5, '14:00', '16:00'), (5, '16:00', '18:00');

-- El viernes siguiente queda bloqueado, para probar fechas bloqueadas.
INSERT INTO fecha_bloqueada (fecha, motivo) VALUES (pg_temp.viernes() + 7, 'Feriado de prueba');

-- -----------------------------------------------------------------------------
-- 1. Overbooking
-- -----------------------------------------------------------------------------
SELECT tomar_hora(pg_temp.usuario('11111111-1'), pg_temp.servicio('Instalación de equipo'),
                  pg_temp.hora(pg_temp.viernes(), '09:00'), 'Calle Uno 123', 'Ñuñoa') AS cita_uno \gset

SELECT pg_temp.verifica(
    (SELECT estado_cita = 'retenida' AND retenida_hasta > now() AND monto = 35000
     FROM cita_servicio WHERE id_cita = :cita_uno),
    '1a. una hora pagada queda retenida, con su monto');

SELECT pg_temp.espera_error(
    format('SELECT tomar_hora(%s, %s, %L, %L, %L)',
           pg_temp.usuario('22222222-2'), pg_temp.servicio('Instalación de equipo'),
           pg_temp.hora(pg_temp.viernes(), '09:00'), 'Calle Dos 456', 'Providencia'),
    'HP001', '1b. una segunda reserva de la misma hora se rechaza (overbooking)');

-- -----------------------------------------------------------------------------
-- 2. Retención vencida
-- -----------------------------------------------------------------------------
UPDATE cita_servicio SET retenida_hasta = now() - interval '1 minute' WHERE id_cita = :cita_uno;

SELECT tomar_hora(pg_temp.usuario('22222222-2'), pg_temp.servicio('Instalación de equipo'),
                  pg_temp.hora(pg_temp.viernes(), '09:00'), 'Calle Dos 456', 'Providencia') AS cita_dos \gset

SELECT pg_temp.verifica(
    (SELECT estado_cita = 'expirada' FROM cita_servicio WHERE id_cita = :cita_uno),
    '2a. al vencer la retención, la hora se libera y la cita anterior queda expirada');

SELECT pg_temp.espera_error(
    format('UPDATE cita_servicio SET estado_cita = %L WHERE id_cita = %s', 'confirmada', :cita_uno),
    '23505', '2b. un pago que llega tarde no puede confirmar una hora que ya tomó otro');

-- -----------------------------------------------------------------------------
-- 3. Horas inválidas
-- -----------------------------------------------------------------------------
SELECT pg_temp.espera_error(
    format('SELECT tomar_hora(%s, %s, %L, %L, %L)',
           pg_temp.usuario('11111111-1'), pg_temp.servicio('Instalación de equipo'),
           pg_temp.hora(pg_temp.viernes(), '10:00'), 'Calle Uno 123', 'Ñuñoa'),
    'HP002', '3a. una hora fuera de bloque se rechaza');

SELECT pg_temp.espera_error(
    format('SELECT tomar_hora(%s, %s, %L, %L, %L)',
           pg_temp.usuario('11111111-1'), pg_temp.servicio('Instalación de equipo'),
           pg_temp.hora(pg_temp.viernes() + 3, '09:00'), 'Calle Uno 123', 'Ñuñoa'),
    'HP002', '3b. un lunes (día sin atención) se rechaza');

SELECT pg_temp.espera_error(
    format('SELECT tomar_hora(%s, %s, %L, %L, %L)',
           pg_temp.usuario('11111111-1'), pg_temp.servicio('Instalación de equipo'),
           pg_temp.hora(pg_temp.viernes() + 7, '09:00'), 'Calle Uno 123', 'Ñuñoa'),
    'HP002', '3c. un viernes bloqueado se rechaza');

SELECT pg_temp.espera_error(
    format('SELECT tomar_hora(%s, %s, %L, %L, %L)',
           pg_temp.usuario('11111111-1'), pg_temp.servicio('Instalación de equipo'),
           pg_temp.hora(pg_temp.viernes() - 14, '09:00'), 'Calle Uno 123', 'Ñuñoa'),
    'HP002', '3d. una hora pasada se rechaza');

-- -----------------------------------------------------------------------------
-- 4. Calendario
-- -----------------------------------------------------------------------------
SELECT pg_temp.verifica(
    (SELECT count(*) = 3 AND NOT bool_or(fecha_hora = pg_temp.hora(pg_temp.viernes(), '09:00'))
     FROM horas_disponibles(pg_temp.viernes())),
    '4a. el calendario del viernes muestra 3 bloques y no la hora tomada');

SELECT pg_temp.verifica(
    (SELECT count(*) = 0 FROM horas_disponibles(pg_temp.viernes() + 7)),
    '4b. el calendario de un viernes bloqueado sale vacío');

SELECT pg_temp.verifica(
    (SELECT count(*) = 0 FROM horas_disponibles(pg_temp.viernes() + 3)),
    '4c. el calendario de un día sin atención sale vacío');

-- -----------------------------------------------------------------------------
-- 5. Servicio gratis
-- -----------------------------------------------------------------------------
SELECT tomar_hora(pg_temp.usuario('11111111-1'), pg_temp.servicio('Inspección gratuita'),
                  pg_temp.hora(pg_temp.viernes(), '11:00'), 'Calle Uno 123', 'Ñuñoa') AS cita_gratis \gset

SELECT pg_temp.verifica(
    (SELECT estado_cita = 'confirmada' AND retenida_hasta IS NULL AND monto = 0
     FROM cita_servicio WHERE id_cita = :cita_gratis),
    '5. la inspección gratuita se confirma sin retención ni pago');

-- -----------------------------------------------------------------------------
-- 6. Reglas de integridad (CHECK y únicos)
-- -----------------------------------------------------------------------------
SELECT pg_temp.espera_error(
    $$INSERT INTO usuario (rut, nombre_completo, correo, contrasena_hash, rol_usuario)
      VALUES ('44444444-4', 'X', 'x@prueba.cl', 'hash', 'jefe')$$,
    '23514', '6a. un rol que no existe se rechaza');

SELECT pg_temp.espera_error(
    $$INSERT INTO usuario (rut, nombre_completo, correo, contrasena_hash)
      VALUES ('44.444.444-4', 'X', 'x@prueba.cl', 'hash')$$,
    '23514', '6b. un RUT con puntos se rechaza');

SELECT pg_temp.espera_error(
    $$INSERT INTO usuario (rut, nombre_completo, correo, contrasena_hash)
      VALUES ('44444444-4', 'X', 'UNO@Prueba.cl', 'hash')$$,
    '23505', '6c. un correo repetido con otras mayúsculas se rechaza');

SELECT pg_temp.espera_error(
    $$UPDATE producto SET stock_disponible = -1 WHERE id_producto = (SELECT min(id_producto) FROM producto)$$,
    '23514', '6d. un stock negativo se rechaza');

INSERT INTO pedido (id_usuario, direccion_despacho, comuna_despacho, monto_total, estado_pedido)
VALUES (pg_temp.usuario('11111111-1'), 'Calle Uno 123', 'Ñuñoa', 90000, 'pendiente_pago')
RETURNING id_pedido AS pedido_uno \gset

SELECT pg_temp.espera_error(
    format($$INSERT INTO detalle_pedido (id_pedido, id_producto, cantidad, precio_unitario_historico, precio_subtotal)
             VALUES (%s, (SELECT min(id_producto) FROM producto), 2, 45000, 80000)$$, :pedido_uno),
    '23514', '6e. un subtotal que no calza con cantidad por precio se rechaza');

SELECT pg_temp.espera_error(
    format('INSERT INTO transaccion_pago (id_pedido, id_cita, monto) VALUES (%s, %s, 1000)', :pedido_uno, :cita_dos),
    '23514', '6f. un pago de un pedido y una cita a la vez se rechaza');

SELECT pg_temp.espera_error(
    'INSERT INTO transaccion_pago (monto) VALUES (1000)',
    '23514', '6g. un pago sin pedido ni cita se rechaza');

SELECT pg_temp.espera_error(
    $$INSERT INTO cotizacion (nombre, correo, telefono, detalle, acepta_politica)
      VALUES ('X', 'x@prueba.cl', '+56911111111', 'Proyecto especial', FALSE)$$,
    '23514', '6h. una cotización sin consentimiento se rechaza');

SELECT pg_temp.espera_error(
    $$INSERT INTO cita_servicio (id_usuario_cliente, id_servicio, direccion_instalacion, comuna,
                                 fecha_hora_reserva, monto, estado_cita)
      VALUES ((SELECT min(id_usuario) FROM usuario), (SELECT min(id_servicio) FROM servicio),
              'Calle', 'Ñuñoa', now() + interval '30 days', 1000, 'retenida')$$,
    '23514', '6i. una cita retenida sin vencimiento se rechaza');

-- -----------------------------------------------------------------------------
-- 7. Vistas de Power BI
-- -----------------------------------------------------------------------------
INSERT INTO detalle_pedido (id_pedido, id_producto, cantidad, precio_unitario_historico, precio_subtotal)
VALUES (:pedido_uno, (SELECT id_producto FROM producto WHERE nombre_producto = 'Filtro Alcalino Remineralizador Pura'),
        2, 45000, 90000);

SELECT pg_temp.verifica(
    (SELECT count(*) = 0 FROM v_ventas_productos_mensual),
    '7a. un pedido sin pagar no cuenta como venta');

UPDATE pedido SET estado_pedido = 'pagado' WHERE id_pedido = :pedido_uno;
UPDATE cita_servicio SET estado_cita = 'confirmada', retenida_hasta = NULL WHERE id_cita = :cita_dos;

SELECT pg_temp.verifica(
    (SELECT pedidos = 1 AND unidades = 2 AND monto = 90000
     FROM v_ventas_productos_mensual
     WHERE mes = date_trunc('month', now() AT TIME ZONE 'America/Santiago')::date),
    '7b. la venta pagada aparece en v_ventas_productos_mensual');

SELECT pg_temp.verifica(
    (SELECT unidades = 2 AND monto = 90000
     FROM v_productos_mas_vendidos WHERE producto = 'Filtro Alcalino Remineralizador Pura'),
    '7c. el producto aparece en v_productos_mas_vendidos');

SELECT pg_temp.verifica(
    (SELECT sum(monto) = 35000 AND sum(citas) = 2
     FROM v_ingresos_servicios_mensual
     WHERE mes = date_trunc('month', now() AT TIME ZONE 'America/Santiago')::date),
    '7d. v_ingresos_servicios_mensual suma las citas confirmadas (35.000 + inspección gratis)');

SELECT pg_temp.verifica(
    (SELECT sum(citas) = 3 FROM v_citas_por_estado),
    '7e. v_citas_por_estado cuenta todas las citas, incluida la expirada');

\echo
\echo 'Todas las pruebas pasaron.'

ROLLBACK;
