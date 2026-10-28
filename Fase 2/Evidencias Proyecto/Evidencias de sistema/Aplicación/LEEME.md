# HidroPura System: aplicación

- **Sitio publicado:** https://hidropura-web-49562663976.southamerica-west1.run.app
- **Código fuente:** repositorio privado [`V-J-C-V/hidropura-web`](https://github.com/V-J-C-V/hidropura-web). Pide acceso a Vicente Carrasco.
- **Base de datos:** el script y las pruebas están en `../Base de datos/`. Las migraciones originales están en `api/db/migraciones/` del repositorio.

## Tecnologías

| Parte | Tecnología |
|---|---|
| Front-end | React 19 + Vite + Tailwind CSS (diseño original en Figma) |
| Back-end | Python 3.12 con FastAPI (API REST en `/api`) y SQL directo con psycopg 3 |
| Base de datos | PostgreSQL 16 en Google Cloud SQL |
| Despliegue | Google Cloud Run: un solo servicio sirve la API y el React compilado |
| Seguridad | Contraseñas con argon2 y sesión JWT en cookie httpOnly. Roles: administrador, trabajador y cliente |
| Chatbot | Asistente de la plataforma Tencavox: configurado; falta incrustar su widget en el sitio (pendiente) |

## Correrla en local

Hace falta Docker y Node 22. Desde la raíz del repositorio `hidropura-web`:

```bash
docker compose up -d db                                   # PostgreSQL en localhost:5435
docker compose --profile pruebas run --rm -e DATABASE_URL=postgresql://hidropura:hidropura@db:5432/hidropura pruebas python db/migrar.py
npm install && npm run dev                                # el sitio, en http://localhost:5173
```

La API se levanta con Python 3.12 como explica `api/README.md`.

## Pruebas

```bash
docker compose --profile pruebas run --rm pruebas         # pruebas de la API (pytest)
docker compose exec -T db psql -U hidropura -d hidropura -v ON_ERROR_STOP=1 < api/db/pruebas_bd.sql   # reglas de la base
```

Los resultados de cada ejecución están en «Resultados de las pruebas», en `Evidencias de documentación/Diseño/`.
