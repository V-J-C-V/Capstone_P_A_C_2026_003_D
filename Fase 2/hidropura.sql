--
-- PostgreSQL database dump
--

\restrict r8PWIkfuGZwQHS91DpFqwlGzT1onRzJcPcUQtA1DnEBgAgcbaRFET3lGzis95It

-- Dumped from database version 16.15
-- Dumped by pg_dump version 16.15

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: horas_disponibles(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.horas_disponibles(p_fecha date) RETURNS TABLE(fecha_hora timestamp with time zone, hora_fin timestamp with time zone)
    LANGUAGE sql STABLE
    AS $$
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


--
-- Name: tomar_hora(integer, integer, timestamp with time zone, character varying, character varying, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tomar_hora(p_cliente integer, p_servicio integer, p_fecha_hora timestamp with time zone, p_direccion character varying, p_comuna character varying, p_minutos integer DEFAULT 15) RETURNS integer
    LANGUAGE plpgsql
    AS $$
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


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: cita_servicio; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cita_servicio (
    id_cita integer NOT NULL,
    id_usuario_cliente integer NOT NULL,
    id_usuario_trabajador integer,
    id_servicio integer NOT NULL,
    direccion_instalacion character varying(255) NOT NULL,
    comuna character varying(80) NOT NULL,
    fecha_hora_reserva timestamp with time zone NOT NULL,
    monto integer NOT NULL,
    estado_cita character varying(20) NOT NULL,
    retenida_hasta timestamp with time zone,
    fecha_creacion timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT cita_servicio_check CHECK ((((estado_cita)::text <> 'retenida'::text) OR (retenida_hasta IS NOT NULL))),
    CONSTRAINT cita_servicio_estado_cita_check CHECK (((estado_cita)::text = ANY ((ARRAY['retenida'::character varying, 'confirmada'::character varying, 'realizada'::character varying, 'cancelada'::character varying, 'expirada'::character varying])::text[]))),
    CONSTRAINT cita_servicio_monto_check CHECK ((monto >= 0))
);


--
-- Name: cita_servicio_id_cita_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cita_servicio_id_cita_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cita_servicio_id_cita_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cita_servicio_id_cita_seq OWNED BY public.cita_servicio.id_cita;


--
-- Name: cotizacion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cotizacion (
    id_cotizacion integer NOT NULL,
    id_usuario integer,
    nombre character varying(150) NOT NULL,
    correo character varying(150) NOT NULL,
    telefono character varying(20) NOT NULL,
    comuna character varying(80),
    detalle text NOT NULL,
    estado character varying(20) DEFAULT 'nueva'::character varying NOT NULL,
    acepta_politica boolean NOT NULL,
    fecha_creacion timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT cotizacion_acepta_politica_check CHECK (acepta_politica),
    CONSTRAINT cotizacion_estado_check CHECK (((estado)::text = ANY ((ARRAY['nueva'::character varying, 'respondida'::character varying, 'cerrada'::character varying])::text[])))
);


--
-- Name: cotizacion_id_cotizacion_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cotizacion_id_cotizacion_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cotizacion_id_cotizacion_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cotizacion_id_cotizacion_seq OWNED BY public.cotizacion.id_cotizacion;


--
-- Name: detalle_pedido; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.detalle_pedido (
    id_detalle integer NOT NULL,
    id_pedido integer NOT NULL,
    id_producto integer NOT NULL,
    cantidad integer NOT NULL,
    precio_unitario_historico integer NOT NULL,
    precio_subtotal integer NOT NULL,
    CONSTRAINT detalle_pedido_cantidad_check CHECK ((cantidad > 0)),
    CONSTRAINT detalle_pedido_check CHECK ((precio_subtotal = (cantidad * precio_unitario_historico))),
    CONSTRAINT detalle_pedido_precio_unitario_historico_check CHECK ((precio_unitario_historico >= 0))
);


--
-- Name: detalle_pedido_id_detalle_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.detalle_pedido_id_detalle_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: detalle_pedido_id_detalle_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.detalle_pedido_id_detalle_seq OWNED BY public.detalle_pedido.id_detalle;


--
-- Name: fecha_bloqueada; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fecha_bloqueada (
    fecha date NOT NULL,
    motivo character varying(200),
    fecha_creacion timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: horario_atencion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.horario_atencion (
    id_horario integer NOT NULL,
    dia_semana smallint NOT NULL,
    hora_inicio time without time zone NOT NULL,
    hora_fin time without time zone NOT NULL,
    estado_activo boolean DEFAULT true NOT NULL,
    fecha_creacion timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT horario_atencion_check CHECK ((hora_fin > hora_inicio)),
    CONSTRAINT horario_atencion_dia_semana_check CHECK (((dia_semana >= 1) AND (dia_semana <= 7)))
);


--
-- Name: horario_atencion_id_horario_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.horario_atencion_id_horario_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: horario_atencion_id_horario_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.horario_atencion_id_horario_seq OWNED BY public.horario_atencion.id_horario;


--
-- Name: migracion_aplicada; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.migracion_aplicada (
    nombre text NOT NULL,
    fecha timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: pedido; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pedido (
    id_pedido integer NOT NULL,
    id_usuario integer NOT NULL,
    direccion_despacho character varying(255),
    comuna_despacho character varying(80),
    fecha_pedido timestamp with time zone DEFAULT now() NOT NULL,
    monto_total integer NOT NULL,
    estado_pedido character varying(20) DEFAULT 'pendiente_pago'::character varying NOT NULL,
    CONSTRAINT pedido_estado_pedido_check CHECK (((estado_pedido)::text = ANY ((ARRAY['pendiente_pago'::character varying, 'pagado'::character varying, 'despachado'::character varying, 'entregado'::character varying, 'cancelado'::character varying])::text[]))),
    CONSTRAINT pedido_monto_total_check CHECK ((monto_total >= 0))
);


--
-- Name: pedido_id_pedido_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.pedido_id_pedido_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: pedido_id_pedido_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.pedido_id_pedido_seq OWNED BY public.pedido.id_pedido;


--
-- Name: producto; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.producto (
    id_producto integer NOT NULL,
    nombre_producto character varying(150) NOT NULL,
    descripcion text,
    tipo character varying(20) NOT NULL,
    marca character varying(80),
    imagen_url character varying(500),
    precio_unitario integer NOT NULL,
    stock_disponible integer NOT NULL,
    estado_activo boolean DEFAULT true NOT NULL,
    fecha_creacion timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT producto_precio_unitario_check CHECK ((precio_unitario >= 0)),
    CONSTRAINT producto_stock_disponible_check CHECK ((stock_disponible >= 0)),
    CONSTRAINT producto_tipo_check CHECK (((tipo)::text = ANY ((ARRAY['equipo'::character varying, 'insumo'::character varying, 'repuesto'::character varying])::text[])))
);


--
-- Name: producto_id_producto_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.producto_id_producto_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: producto_id_producto_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.producto_id_producto_seq OWNED BY public.producto.id_producto;


--
-- Name: servicio; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.servicio (
    id_servicio integer NOT NULL,
    nombre character varying(100) NOT NULL,
    descripcion text,
    precio integer NOT NULL,
    estado_activo boolean DEFAULT true NOT NULL,
    fecha_creacion timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT servicio_precio_check CHECK ((precio >= 0))
);


--
-- Name: servicio_id_servicio_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.servicio_id_servicio_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: servicio_id_servicio_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.servicio_id_servicio_seq OWNED BY public.servicio.id_servicio;


--
-- Name: transaccion_pago; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.transaccion_pago (
    id_transaccion integer NOT NULL,
    id_pedido integer,
    id_cita integer,
    preference_id character varying(255),
    codigo_mercadopago character varying(255),
    monto integer NOT NULL,
    estado_pago character varying(20) DEFAULT 'pendiente'::character varying NOT NULL,
    fecha_pago timestamp with time zone,
    fecha_creacion timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT transaccion_pago_check CHECK ((num_nonnulls(id_pedido, id_cita) = 1)),
    CONSTRAINT transaccion_pago_estado_pago_check CHECK (((estado_pago)::text = ANY ((ARRAY['pendiente'::character varying, 'aprobado'::character varying, 'rechazado'::character varying, 'cancelado'::character varying, 'reembolsado'::character varying])::text[]))),
    CONSTRAINT transaccion_pago_monto_check CHECK ((monto > 0))
);


--
-- Name: transaccion_pago_id_transaccion_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.transaccion_pago_id_transaccion_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: transaccion_pago_id_transaccion_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.transaccion_pago_id_transaccion_seq OWNED BY public.transaccion_pago.id_transaccion;


--
-- Name: usuario; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usuario (
    id_usuario integer NOT NULL,
    rut character varying(12) NOT NULL,
    nombre_completo character varying(150) NOT NULL,
    correo character varying(150) NOT NULL,
    contrasena_hash character varying(255) NOT NULL,
    telefono character varying(20),
    rol_usuario character varying(20) DEFAULT 'cliente'::character varying NOT NULL,
    estado_activo boolean DEFAULT true NOT NULL,
    token_recuperacion_hash character varying(255),
    token_recuperacion_expira timestamp with time zone,
    acepta_politica boolean DEFAULT false NOT NULL,
    fecha_aceptacion_politica timestamp with time zone,
    acepta_marketing boolean DEFAULT false NOT NULL,
    fecha_creacion timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT usuario_check CHECK (((NOT acepta_politica) OR (fecha_aceptacion_politica IS NOT NULL))),
    CONSTRAINT usuario_rol_usuario_check CHECK (((rol_usuario)::text = ANY ((ARRAY['administrador'::character varying, 'trabajador'::character varying, 'cliente'::character varying])::text[]))),
    CONSTRAINT usuario_rut_check CHECK (((rut)::text ~ '^[0-9]{7,8}-[0-9K]$'::text))
);


--
-- Name: usuario_id_usuario_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.usuario_id_usuario_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: usuario_id_usuario_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.usuario_id_usuario_seq OWNED BY public.usuario.id_usuario;


--
-- Name: v_citas_por_estado; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_citas_por_estado AS
 SELECT (date_trunc('month'::text, (fecha_hora_reserva AT TIME ZONE 'America/Santiago'::text)))::date AS mes,
    estado_cita AS estado,
    count(*) AS citas
   FROM public.cita_servicio c
  GROUP BY ((date_trunc('month'::text, (fecha_hora_reserva AT TIME ZONE 'America/Santiago'::text)))::date), estado_cita;


--
-- Name: v_cotizaciones_mensual; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_cotizaciones_mensual AS
 SELECT (date_trunc('month'::text, (fecha_creacion AT TIME ZONE 'America/Santiago'::text)))::date AS mes,
    estado,
    count(*) AS cotizaciones
   FROM public.cotizacion
  GROUP BY ((date_trunc('month'::text, (fecha_creacion AT TIME ZONE 'America/Santiago'::text)))::date), estado;


--
-- Name: v_ingresos_servicios_mensual; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_ingresos_servicios_mensual AS
 SELECT (date_trunc('month'::text, (c.fecha_creacion AT TIME ZONE 'America/Santiago'::text)))::date AS mes,
    s.nombre AS servicio,
    count(*) AS citas,
    sum(c.monto) AS monto
   FROM (public.cita_servicio c
     JOIN public.servicio s ON ((s.id_servicio = c.id_servicio)))
  WHERE ((c.estado_cita)::text = ANY ((ARRAY['confirmada'::character varying, 'realizada'::character varying])::text[]))
  GROUP BY ((date_trunc('month'::text, (c.fecha_creacion AT TIME ZONE 'America/Santiago'::text)))::date), s.nombre;


--
-- Name: v_productos_mas_vendidos; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_productos_mas_vendidos AS
 SELECT pr.id_producto,
    pr.nombre_producto AS producto,
    pr.tipo,
    pr.marca,
    sum(d.cantidad) AS unidades,
    sum(d.precio_subtotal) AS monto
   FROM ((public.detalle_pedido d
     JOIN public.pedido p ON ((p.id_pedido = d.id_pedido)))
     JOIN public.producto pr ON ((pr.id_producto = d.id_producto)))
  WHERE ((p.estado_pedido)::text = ANY ((ARRAY['pagado'::character varying, 'despachado'::character varying, 'entregado'::character varying])::text[]))
  GROUP BY pr.id_producto, pr.nombre_producto, pr.tipo, pr.marca;


--
-- Name: v_ventas_productos_mensual; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_ventas_productos_mensual AS
 SELECT (date_trunc('month'::text, (p.fecha_pedido AT TIME ZONE 'America/Santiago'::text)))::date AS mes,
    count(DISTINCT p.id_pedido) AS pedidos,
    sum(d.cantidad) AS unidades,
    sum(d.precio_subtotal) AS monto
   FROM (public.pedido p
     JOIN public.detalle_pedido d ON ((d.id_pedido = p.id_pedido)))
  WHERE ((p.estado_pedido)::text = ANY ((ARRAY['pagado'::character varying, 'despachado'::character varying, 'entregado'::character varying])::text[]))
  GROUP BY ((date_trunc('month'::text, (p.fecha_pedido AT TIME ZONE 'America/Santiago'::text)))::date);


--
-- Name: cita_servicio id_cita; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cita_servicio ALTER COLUMN id_cita SET DEFAULT nextval('public.cita_servicio_id_cita_seq'::regclass);


--
-- Name: cotizacion id_cotizacion; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cotizacion ALTER COLUMN id_cotizacion SET DEFAULT nextval('public.cotizacion_id_cotizacion_seq'::regclass);


--
-- Name: detalle_pedido id_detalle; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.detalle_pedido ALTER COLUMN id_detalle SET DEFAULT nextval('public.detalle_pedido_id_detalle_seq'::regclass);


--
-- Name: horario_atencion id_horario; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.horario_atencion ALTER COLUMN id_horario SET DEFAULT nextval('public.horario_atencion_id_horario_seq'::regclass);


--
-- Name: pedido id_pedido; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pedido ALTER COLUMN id_pedido SET DEFAULT nextval('public.pedido_id_pedido_seq'::regclass);


--
-- Name: producto id_producto; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto ALTER COLUMN id_producto SET DEFAULT nextval('public.producto_id_producto_seq'::regclass);


--
-- Name: servicio id_servicio; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.servicio ALTER COLUMN id_servicio SET DEFAULT nextval('public.servicio_id_servicio_seq'::regclass);


--
-- Name: transaccion_pago id_transaccion; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transaccion_pago ALTER COLUMN id_transaccion SET DEFAULT nextval('public.transaccion_pago_id_transaccion_seq'::regclass);


--
-- Name: usuario id_usuario; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario ALTER COLUMN id_usuario SET DEFAULT nextval('public.usuario_id_usuario_seq'::regclass);


--
-- Data for Name: cita_servicio; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.cita_servicio (id_cita, id_usuario_cliente, id_usuario_trabajador, id_servicio, direccion_instalacion, comuna, fecha_hora_reserva, monto, estado_cita, retenida_hasta, fecha_creacion) FROM stdin;
\.


--
-- Data for Name: cotizacion; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.cotizacion (id_cotizacion, id_usuario, nombre, correo, telefono, comuna, detalle, estado, acepta_politica, fecha_creacion) FROM stdin;
\.


--
-- Data for Name: detalle_pedido; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.detalle_pedido (id_detalle, id_pedido, id_producto, cantidad, precio_unitario_historico, precio_subtotal) FROM stdin;
\.


--
-- Data for Name: fecha_bloqueada; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.fecha_bloqueada (fecha, motivo, fecha_creacion) FROM stdin;
\.


--
-- Data for Name: horario_atencion; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.horario_atencion (id_horario, dia_semana, hora_inicio, hora_fin, estado_activo, fecha_creacion) FROM stdin;
1	5	09:00:00	11:00:00	t	2026-10-10 19:27:13.720397-03
2	5	11:00:00	13:00:00	t	2026-10-10 19:27:13.720397-03
3	5	14:00:00	16:00:00	t	2026-10-10 19:27:13.720397-03
4	5	16:00:00	18:00:00	t	2026-10-10 19:27:13.720397-03
\.


--
-- Data for Name: migracion_aplicada; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.migracion_aplicada (nombre, fecha) FROM stdin;
0001_esquema_v2.sql	2026-10-10 19:27:13.588011-03
0002_datos.sql	2026-10-10 19:27:13.720397-03
\.


--
-- Data for Name: pedido; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.pedido (id_pedido, id_usuario, direccion_despacho, comuna_despacho, fecha_pedido, monto_total, estado_pedido) FROM stdin;
\.


--
-- Data for Name: producto; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.producto (id_producto, nombre_producto, descripcion, tipo, marca, imagen_url, precio_unitario, stock_disponible, estado_activo, fecha_creacion) FROM stdin;
1	Purificador T-Water Flujo Directo 1800L	Purificador de flujo directo bajo mesón.	equipo	OSMOAQUA	https://images.unsplash.com/photo-1758560936904-4eb0049284aa?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixlib=rb-4.1.0&q=80&w=600	250000	10	t	2026-10-10 19:27:13.720397-03
2	Filtro Alcalino Remineralizador Pura	Cartucho que remineraliza y alcaliniza el agua.	insumo	HIDROPURA	https://images.unsplash.com/photo-1616118132534-381148898bb4?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixlib=rb-4.1.0&q=80&w=600	45000	20	t	2026-10-10 19:27:13.720397-03
3	Sistema Ósmosis Inversa 5 Etapas	Sistema de ósmosis inversa de cinco etapas.	equipo	OSMOAQUA	https://images.unsplash.com/photo-1616118133103-baf54a4790c6?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixlib=rb-4.1.0&q=80&w=600	180000	8	t	2026-10-10 19:27:13.720397-03
4	Dispensador Agua Fría y Caliente	Dispensador con agua fría y caliente.	equipo	HIDROPURA	https://images.unsplash.com/photo-1756575433595-c2f87d10e5f4?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixlib=rb-4.1.0&q=80&w=600	320000	5	t	2026-10-10 19:27:13.720397-03
5	Cartucho Sedimentos PP 5 Micras	Cartucho de polipropileno para sedimentos.	insumo	OSMOAQUA	https://images.unsplash.com/photo-1758560936904-4eb0049284aa?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixlib=rb-4.1.0&q=80&w=600	12000	50	t	2026-10-10 19:27:13.720397-03
6	Medidor TDS Digital Portátil	Mide los sólidos disueltos totales del agua.	equipo	HIDROPURA	https://images.unsplash.com/photo-1616118132534-381148898bb4?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixlib=rb-4.1.0&q=80&w=600	25000	15	t	2026-10-10 19:27:13.720397-03
7	Membrana de Ósmosis Reversa 75 GPD	Membrana de recambio para ósmosis inversa.	repuesto	OSMOAQUA	https://images.unsplash.com/photo-1616118133103-baf54a4790c6?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixlib=rb-4.1.0&q=80&w=600	38000	12	t	2026-10-10 19:27:13.720397-03
8	Sal para Ablandador 25 kg	Sal en pastillas para regenerar ablandadores.	insumo	HIDROPURA	https://images.unsplash.com/photo-1756575433595-c2f87d10e5f4?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixlib=rb-4.1.0&q=80&w=600	15000	40	t	2026-10-10 19:27:13.720397-03
\.


--
-- Data for Name: servicio; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.servicio (id_servicio, nombre, descripcion, precio, estado_activo, fecha_creacion) FROM stdin;
1	Instalación de equipo	Instalación de ablandadores y purificadores. Garantía de 1 año en mano de obra.	35000	t	2026-10-10 19:27:13.720397-03
2	Mantenimiento de insumos	Cambio de cartuchos, membranas y sales con revisión del sistema.	25000	t	2026-10-10 19:27:13.720397-03
3	Inspección gratuita	Primera visita sin costo para evaluar la instalación.	0	t	2026-10-10 19:27:13.720397-03
\.


--
-- Data for Name: transaccion_pago; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.transaccion_pago (id_transaccion, id_pedido, id_cita, preference_id, codigo_mercadopago, monto, estado_pago, fecha_pago, fecha_creacion) FROM stdin;
\.


--
-- Data for Name: usuario; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.usuario (id_usuario, rut, nombre_completo, correo, contrasena_hash, telefono, rol_usuario, estado_activo, token_recuperacion_hash, token_recuperacion_expira, acepta_politica, fecha_aceptacion_politica, acepta_marketing, fecha_creacion) FROM stdin;
\.


--
-- Name: cita_servicio_id_cita_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.cita_servicio_id_cita_seq', 5, true);


--
-- Name: cotizacion_id_cotizacion_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.cotizacion_id_cotizacion_seq', 1, true);


--
-- Name: detalle_pedido_id_detalle_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.detalle_pedido_id_detalle_seq', 2, true);


--
-- Name: horario_atencion_id_horario_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.horario_atencion_id_horario_seq', 8, true);


--
-- Name: pedido_id_pedido_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.pedido_id_pedido_seq', 1, true);


--
-- Name: producto_id_producto_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.producto_id_producto_seq', 8, true);


--
-- Name: servicio_id_servicio_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.servicio_id_servicio_seq', 3, true);


--
-- Name: transaccion_pago_id_transaccion_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.transaccion_pago_id_transaccion_seq', 2, true);


--
-- Name: usuario_id_usuario_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.usuario_id_usuario_seq', 7, true);


--
-- Name: cita_servicio cita_servicio_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cita_servicio
    ADD CONSTRAINT cita_servicio_pkey PRIMARY KEY (id_cita);


--
-- Name: cotizacion cotizacion_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cotizacion
    ADD CONSTRAINT cotizacion_pkey PRIMARY KEY (id_cotizacion);


--
-- Name: detalle_pedido detalle_pedido_id_pedido_id_producto_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.detalle_pedido
    ADD CONSTRAINT detalle_pedido_id_pedido_id_producto_key UNIQUE (id_pedido, id_producto);


--
-- Name: detalle_pedido detalle_pedido_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.detalle_pedido
    ADD CONSTRAINT detalle_pedido_pkey PRIMARY KEY (id_detalle);


--
-- Name: fecha_bloqueada fecha_bloqueada_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fecha_bloqueada
    ADD CONSTRAINT fecha_bloqueada_pkey PRIMARY KEY (fecha);


--
-- Name: horario_atencion horario_atencion_dia_semana_hora_inicio_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.horario_atencion
    ADD CONSTRAINT horario_atencion_dia_semana_hora_inicio_key UNIQUE (dia_semana, hora_inicio);


--
-- Name: horario_atencion horario_atencion_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.horario_atencion
    ADD CONSTRAINT horario_atencion_pkey PRIMARY KEY (id_horario);


--
-- Name: migracion_aplicada migracion_aplicada_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.migracion_aplicada
    ADD CONSTRAINT migracion_aplicada_pkey PRIMARY KEY (nombre);


--
-- Name: pedido pedido_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pedido
    ADD CONSTRAINT pedido_pkey PRIMARY KEY (id_pedido);


--
-- Name: producto producto_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto
    ADD CONSTRAINT producto_pkey PRIMARY KEY (id_producto);


--
-- Name: servicio servicio_nombre_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.servicio
    ADD CONSTRAINT servicio_nombre_key UNIQUE (nombre);


--
-- Name: servicio servicio_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.servicio
    ADD CONSTRAINT servicio_pkey PRIMARY KEY (id_servicio);


--
-- Name: transaccion_pago transaccion_pago_codigo_mercadopago_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transaccion_pago
    ADD CONSTRAINT transaccion_pago_codigo_mercadopago_key UNIQUE (codigo_mercadopago);


--
-- Name: transaccion_pago transaccion_pago_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transaccion_pago
    ADD CONSTRAINT transaccion_pago_pkey PRIMARY KEY (id_transaccion);


--
-- Name: usuario usuario_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario
    ADD CONSTRAINT usuario_pkey PRIMARY KEY (id_usuario);


--
-- Name: usuario usuario_rut_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario
    ADD CONSTRAINT usuario_rut_key UNIQUE (rut);


--
-- Name: cita_cliente; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX cita_cliente ON public.cita_servicio USING btree (id_usuario_cliente);


--
-- Name: cita_fecha_hora; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX cita_fecha_hora ON public.cita_servicio USING btree (fecha_hora_reserva);


--
-- Name: cita_hora_ocupada; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX cita_hora_ocupada ON public.cita_servicio USING btree (fecha_hora_reserva) WHERE ((estado_cita)::text = ANY ((ARRAY['retenida'::character varying, 'confirmada'::character varying, 'realizada'::character varying])::text[]));


--
-- Name: cita_servicio_fk; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX cita_servicio_fk ON public.cita_servicio USING btree (id_servicio);


--
-- Name: cita_trabajador; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX cita_trabajador ON public.cita_servicio USING btree (id_usuario_trabajador);


--
-- Name: cotizacion_usuario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX cotizacion_usuario ON public.cotizacion USING btree (id_usuario);


--
-- Name: detalle_producto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX detalle_producto ON public.detalle_pedido USING btree (id_producto);


--
-- Name: pedido_usuario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pedido_usuario ON public.pedido USING btree (id_usuario);


--
-- Name: transaccion_cita; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX transaccion_cita ON public.transaccion_pago USING btree (id_cita);


--
-- Name: transaccion_pedido; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX transaccion_pedido ON public.transaccion_pago USING btree (id_pedido);


--
-- Name: usuario_correo_unico; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX usuario_correo_unico ON public.usuario USING btree (lower((correo)::text));


--
-- Name: cita_servicio cita_servicio_id_servicio_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cita_servicio
    ADD CONSTRAINT cita_servicio_id_servicio_fkey FOREIGN KEY (id_servicio) REFERENCES public.servicio(id_servicio);


--
-- Name: cita_servicio cita_servicio_id_usuario_cliente_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cita_servicio
    ADD CONSTRAINT cita_servicio_id_usuario_cliente_fkey FOREIGN KEY (id_usuario_cliente) REFERENCES public.usuario(id_usuario);


--
-- Name: cita_servicio cita_servicio_id_usuario_trabajador_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cita_servicio
    ADD CONSTRAINT cita_servicio_id_usuario_trabajador_fkey FOREIGN KEY (id_usuario_trabajador) REFERENCES public.usuario(id_usuario);


--
-- Name: cotizacion cotizacion_id_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cotizacion
    ADD CONSTRAINT cotizacion_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario);


--
-- Name: detalle_pedido detalle_pedido_id_pedido_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.detalle_pedido
    ADD CONSTRAINT detalle_pedido_id_pedido_fkey FOREIGN KEY (id_pedido) REFERENCES public.pedido(id_pedido) ON DELETE CASCADE;


--
-- Name: detalle_pedido detalle_pedido_id_producto_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.detalle_pedido
    ADD CONSTRAINT detalle_pedido_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);


--
-- Name: pedido pedido_id_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pedido
    ADD CONSTRAINT pedido_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario);


--
-- Name: transaccion_pago transaccion_pago_id_cita_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transaccion_pago
    ADD CONSTRAINT transaccion_pago_id_cita_fkey FOREIGN KEY (id_cita) REFERENCES public.cita_servicio(id_cita);


--
-- Name: transaccion_pago transaccion_pago_id_pedido_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transaccion_pago
    ADD CONSTRAINT transaccion_pago_id_pedido_fkey FOREIGN KEY (id_pedido) REFERENCES public.pedido(id_pedido);


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

GRANT ALL ON SCHEMA public TO cloudsqlsuperuser;


--
-- PostgreSQL database dump complete
--

\unrestrict r8PWIkfuGZwQHS91DpFqwlGzT1onRzJcPcUQtA1DnEBgAgcbaRFET3lGzis95It

