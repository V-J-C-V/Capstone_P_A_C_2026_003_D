-- =============================================================================
-- HidroPura System - Datos iniciales de ejemplo para la v2
-- Productos tomados del catálogo actual de la web (hidropura-web/src/App.tsx).
-- Stock, precios de servicios y horas de los bloques son de EJEMPLO: confirmar con Cristian.
-- =============================================================================

INSERT INTO producto (nombre_producto, descripcion, tipo, marca, imagen_url, precio_unitario, stock_disponible) VALUES
('Purificador T-Water Flujo Directo 1800L', 'Purificador de flujo directo bajo mesón.', 'equipo', 'OSMOAQUA',
 'https://images.unsplash.com/photo-1758560936904-4eb0049284aa?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixlib=rb-4.1.0&q=80&w=600', 250000, 10),
('Filtro Alcalino Remineralizador Pura', 'Cartucho que remineraliza y alcaliniza el agua.', 'insumo', 'HIDROPURA',
 'https://images.unsplash.com/photo-1616118132534-381148898bb4?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixlib=rb-4.1.0&q=80&w=600', 45000, 20),
('Sistema Ósmosis Inversa 5 Etapas', 'Sistema de ósmosis inversa de cinco etapas.', 'equipo', 'OSMOAQUA',
 'https://images.unsplash.com/photo-1616118133103-baf54a4790c6?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixlib=rb-4.1.0&q=80&w=600', 180000, 8),
('Dispensador Agua Fría y Caliente', 'Dispensador con agua fría y caliente.', 'equipo', 'HIDROPURA',
 'https://images.unsplash.com/photo-1756575433595-c2f87d10e5f4?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixlib=rb-4.1.0&q=80&w=600', 320000, 5),
('Cartucho Sedimentos PP 5 Micras', 'Cartucho de polipropileno para sedimentos.', 'insumo', 'OSMOAQUA',
 'https://images.unsplash.com/photo-1758560936904-4eb0049284aa?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixlib=rb-4.1.0&q=80&w=600', 12000, 50),
('Medidor TDS Digital Portátil', 'Mide los sólidos disueltos totales del agua.', 'equipo', 'HIDROPURA',
 'https://images.unsplash.com/photo-1616118132534-381148898bb4?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixlib=rb-4.1.0&q=80&w=600', 25000, 15),
('Membrana de Ósmosis Reversa 75 GPD', 'Membrana de recambio para ósmosis inversa.', 'repuesto', 'OSMOAQUA',
 'https://images.unsplash.com/photo-1616118133103-baf54a4790c6?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixlib=rb-4.1.0&q=80&w=600', 38000, 12),
('Sal para Ablandador 25 kg', 'Sal en pastillas para regenerar ablandadores.', 'insumo', 'HIDROPURA',
 'https://images.unsplash.com/photo-1756575433595-c2f87d10e5f4?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixlib=rb-4.1.0&q=80&w=600', 15000, 40);

INSERT INTO servicio (nombre, descripcion, precio) VALUES
('Instalación de equipo', 'Instalación de ablandadores y purificadores. Garantía de 1 año en mano de obra.', 35000),
('Mantenimiento de insumos', 'Cambio de cartuchos, membranas y sales con revisión del sistema.', 25000),
('Inspección gratuita', 'Primera visita sin costo para evaluar la instalación.', 0);

-- Por ahora Cristian atiende solo los viernes (5 = viernes en ISO).
-- Cuatro bloques de 2 horas: 09, 11, 14 y 16 (horas por confirmar).
INSERT INTO horario_atencion (dia_semana, hora_inicio, hora_fin)
SELECT 5, h, h + interval '2 hours'
FROM unnest(ARRAY[time '09:00', time '11:00', time '14:00', time '16:00']) AS h;
