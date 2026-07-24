# Poste.io Mail Server - canastia.pe

Servidor de correo completo basado en [Poste.io](https://poste.io) para el dominio **canastia.pe**.

Proyecto Docker independiente. No interfiere con el proyecto principal (`comparadorBackendFast`).

---

## Estructura del Proyecto

```
Mail Server/
├── docker-compose.yml    # Definición del servicio Poste.io
├── .env                  # Variables de entorno (producción)
├── .env.example          # Plantilla de variables de entorno
├── .gitignore
├── README.md
├── data/                 # Datos persistentes (correos, cuentas, configuración)
├── backups/              # Directorio para backups
└── scripts/
    └── backup.sh         # Script de backup sin downtime
```

---

## Requisitos

- Docker y Docker Compose instalados
- Puerto **25** (SMTP) abierto en el firewall del VPS
- Puertos **465, 587, 993** abiertos en el firewall
- Registros DNS configurados (ver sección DNS más abajo)

---

## Instalación

### 1. Crear la red Docker compartida

```bash
docker network create shared-network
```

Esta red permite que los contenedores de proyectos independientes se comuniquen por nombre de contenedor. El proyecto `comparadorBackendFast` se conectará a esta misma red cuando se configure el reverse proxy para `mail.canastia.pe`.

### 2. Copiar el proyecto al VPS

```bash
mkdir -p /root/comparador/posteio
cd /root/comparador/posteio
# Copiar todos los archivos aquí
```

### 3. Configurar variables de entorno

```bash
cp .env.example .env
nano .env
```

### 4. Levantar el contenedor

```bash
docker compose up -d
```

La primera vez tarda 2-3 minutos en inicializar (genera certificados internos, configura Postfix, Dovecot, etc.).

### 5. Verificar

```bash
docker compose ps
docker compose logs -f
```

Cuando veas `poste.io is running`, el servidor está listo.

---

## Acceso a la Interfaz de Administración

Una vez corriendo:

- **URL:** `http://mail.canastia.pe:8080`
- **Primer acceso:** crea la cuenta de administrador siguiendo el asistente
- Selecciona el dominio `canastia.pe` durante la configuración inicial

> La interfaz usa HTTP simple porque `HTTPS=OFF` en Poste.io.
> El HTTPS (certificado Let's Encrypt) lo manejará Nginx del proyecto principal
> cuando se configure el reverse proxy para `mail.canastia.pe`.

---

## Crear Cuentas de Correo

Desde la interfaz de administración:

1. Ve a **Virtual domains** → `canastia.pe`
2. Haz clic en **Create mailbox**
3. Asigna nombre, contraseña y quota

Ejemplos de cuentas:

```
no-reply@canastia.pe    → Para envíos automáticos del backend
admin@canastia.pe       → Administración
info@canastia.pe        → Contacto público
```

---

## Conectar el Backend FastAPI

En el archivo `.env` del proyecto `comparadorBackendFast`, actualizar:

```env
SMTP_SERVER=mail.canastia.pe
SMTP_PORT=587
SMTP_USERNAME=no-reply@canastia.pe
SMTP_PASSWORD=la-contraseña-que-creaste
EMAIL_FROM=no-reply@canastia.pe
```

El backend se comunica con Poste.io usando SMTP en el puerto 587 (STARTTLS). **No requiere modificar el código Python.**

---

## Registros DNS en GoDaddy

### Orden de creación

Los registros deben crearse en este orden para evitar rechazos de correo:

| Paso | Tipo  | Nombre | Valor                        | Prioridad | Cuándo |
|------|-------|--------|------------------------------|-----------|--------|
| 1    | **A** | `mail` | `62.169.24.231`              | —         | **Inmediato** (antes de levantar) |
| 2    | **MX**| `@`    | `mail.canastia.pe`           | 10        | **Inmediato** (después del A) |
| 3    | **TXT**| `@`   | `v=spf1 mx ~all`             | —         | **Inmediato** (junto con MX) |
| 4    | **TXT**| `@`   | *(generado por Poste.io)*    | —         | **Después** de crear el dominio en Poste.io |
| 5    | **TXT**| `@`   | `v=DMARC1; p=none; rua=mailto:admin@canastia.pe` | — | **Después** de verificar que todo funciona |

**Explicación del orden:**

- **A + MX**: Sin esto no se puede recibir correo. El registro A para `mail` debe existir antes que el MX.
- **SPF**: Autoriza al VPS como remitente legítimo. Sin SPF, muchos servidores rechazarán tus correos.
- **DKIM**: Poste.io genera la clave al crear el dominio. Copia el registro TXT desde **Virtual domains → canastia.pe → DKIM** y pégalo en GoDaddy.
- **DMARC**: Configúralo al final, empezando con `p=none` (solo monitoreo, no rechazo). Cuando todo funcione correctamente, sube a `p=quarantine` o `p=reject`.

---

## Puertos

| Puerto | Protocolo | Propósito                          | Expuesto |
|--------|-----------|------------------------------------|----------|
| 25     | SMTP      | Recepción de correo entrante       | SÍ       |
| 465    | SMTPS     | Envío saliente (SSL implícito)     | SÍ       |
| 587    | Submission| Envío saliente (STARTTLS)          | SÍ       |
| 993    | IMAPS     | Acceso a buzones (SSL)             | SÍ       |
| 4190   | Sieve     | Filtros de correo                  | SÍ       |
| 8080   | HTTP      | Interfaz web de administración     | SÍ       |

> **No se expone HTTPS (443) desde Poste.io.** El `HTTPS=OFF` desactiva SSL interno.
> Nginx del proyecto principal actuará como terminador SSL usando Let's Encrypt.

---

## Volúmenes

| Volumen     | Ruta en host | Ruta en contenedor | Descripción                            |
|-------------|-------------|--------------------|----------------------------------------|
| `./data`    | `./data`    | `/data`            | Correos, cuentas, config, DKIM, logs   |

Todo el estado de Poste.io se almacena en `./data/`. Este directorio debe respaldarse regularmente.

---

## Backups

### Backup manual

```bash
docker compose stop
tar -czf backups/posteio-backup-$(date +%Y%m%d).tar.gz data/
docker compose start
```

### Backup sin detener (recomendado para producción)

```bash
docker compose exec mailserver tar -czf /tmp/backup.tar.gz /data
docker cp posteio:/tmp/backup.tar.gz backups/posteio-backup-$(date +%Y%m%d).tar.gz
```

### Restaurar

```bash
docker compose stop
rm -rf data/
tar -xzf backups/posteio-backup-YYYYMMDD.tar.gz
docker compose start
```

---

## Configuración Futura: Nginx Reverse Proxy

Cuando se quiera exponer `mail.canastia.pe` con HTTPS usando Let's Encrypt (sin el puerto 8080):

### Arquitectura de comunicación

Ambos proyectos (`comparadorBackendFast` y `posteio`) comparten la red Docker `shared-network`. Esto permite que Nginx resuelva el contenedor de Poste.io por su nombre (`posteio`) sin usar la IP pública del VPS.

```
Internet (HTTPS)
    │
    ▼
Nginx (comparadorBackendFast)
    │  server_name mail.canastia.pe
    │  proxy_pass http://posteio:80
    │
    ▼
Poste.io (este proyecto)
    │  container_name: posteio
    │  red: shared-network
```

### Pasos para habilitar el reverse proxy

#### 1. Conectar el proyecto principal a la red compartida

En `comparadorBackendFast/docker-compose.yml`, añadir al servicio `nginx`:

```yaml
networks:
  - app-network
  - shared-network     # ← añadir

networks:
  app-network:
    driver: bridge
  shared-network:       # ← añadir al final
    external: true
```

#### 2. Crear archivo de configuración Nginx para Poste.io

Crear `comparadorBackendFast/nginx/posteio.conf`:

```nginx
server {
    listen 443 ssl http2;
    server_name mail.canastia.pe;

    ssl_certificate     /etc/letsencrypt/live/canastia.pe/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/canastia.pe/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        proxy_pass http://posteio:80;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        client_max_body_size 50M;
    }
}
```

> **`proxy_pass http://posteio:80`** — resuelve por nombre de contenedor vía `shared-network`. Sin IPs hardcodeadas.

#### 3. Expandir el certificado Let's Encrypt

```bash
certbot certonly --cert-name canastia.pe \
  -d canastia.pe -d www.canastia.pe -d mail.canastia.pe \
  --standalone
```

#### 4. Reiniciar Nginx

```bash
cd /opt/comparador/comparadorBackendFast
docker compose restart nginx
```

#### 5. Cerrar puerto 8080 en el firewall

Una vez funcionando el proxy, el puerto 8080 puede cerrarse:

```bash
sudo ufw deny 8080
```

---

## Comandos Útiles

```bash
# Ver estado
docker compose ps

# Ver logs
docker compose logs -f

# Reiniciar
docker compose restart

# Detener
docker compose stop

# Levantar
docker compose up -d

# Entrar al contenedor
docker compose exec mailserver bash
```

---

## Solución de Problemas

### El contenedor no arranca

```bash
docker compose logs mailserver
```

Causa común: la red `shared-network` no existe. Crear con:
```bash
docker network create shared-network
```

### Los correos no llegan

1. Verificar que el puerto 25 está abierto: `lsof -i :25`
2. Verificar registros MX: `nslookup -type=MX canastia.pe`
3. Verificar log de Postfix: `docker compose exec mailserver tail -f /var/log/mail.log`

### No puedo acceder a la interfaz web

- Asegúrate de usar `http://` (no `https://`)
- Verifica que el puerto 8080 está abierto: `lsof -i :8080`
