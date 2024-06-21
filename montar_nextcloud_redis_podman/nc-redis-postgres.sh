#!/bin/bash

# Definir variables predeterminadas
POSTGRES_PASS="Pil20000"
POSTGRES_USER="nextcloud"
NEXTCLOUD_ADMIN_USER="pilevante"
NEXTCLOUD_ADMIN_PASSWORD="Pil20000"
PORT="9999"
DATA_DIR="/mnt/nc/data"
CONFIG_DIR="/mnt/nc/config"
DB_DIR="/mnt/nc/db"
POD_NAME="nc"

# Función de ayuda
function show_help {
    echo "Uso: $0 [-p PASSWORD] [-u USER] [-a ADMIN_USER] [-b ADMIN_PASSWORD] [-d DATA_DIR] [-c CONFIG_DIR] [-r DB_DIR] [-o PORT] [-n POD_NAME]"
    echo "Options:"
    echo "  -p  Contraseña para la base de datos PostgreSQL (por defecto: Pil20000)"
    echo "  -u  Usuario para la base de datos PostgreSQL (por defecto: nextcloud)"
    echo "  -a  Usuario administrador de Nextcloud (por defecto: pilevante)"
    echo "  -b  Contraseña del usuario administrador de Nextcloud (por defecto: Pil20000)"
    echo "  -d  Directorio donde se almacenarán los datos de Nextcloud (por defecto: /mnt/nc/data)"
    echo "  -c  Directorio donde se almacenará la configuración de Nextcloud (por defecto: /mnt/nc/config)"
    echo "  -r  Directorio donde se almacenarán los datos de la base de datos PostgreSQL (por defecto: /mnt/nc/db)"
    echo "  -o  Puerto para exponer Nextcloud (por defecto: 9999)"
    echo "  -n  Nombre del pod (por defecto: nc)"
    exit 1
}

# Parsear opciones
while getopts ":p:u:a:b:d:c:r:o:n:h" opt; do
    case ${opt} in
        p )
            POSTGRES_PASS=$OPTARG
            ;;
        u )
            POSTGRES_USER=$OPTARG
            ;;
        a )
            NEXTCLOUD_ADMIN_USER=$OPTARG
            ;;
        b )
            NEXTCLOUD_ADMIN_PASSWORD=$OPTARG
            ;;
        d )
            DATA_DIR=$OPTARG
            ;;
        c )
            CONFIG_DIR=$OPTARG
            ;;
        r )
            DB_DIR=$OPTARG
            ;;
        o )
            PORT=$OPTARG
            ;;
        n )
            POD_NAME=$OPTARG
            ;;
        h )
            show_help
            ;;
        \? )
            echo "Opción no válida: -$OPTARG" 1>&2
            show_help
            ;;
    esac
done

# Crear directorios para los volúmenes persistentes si no existen
mkdir -p $DATA_DIR
mkdir -p $CONFIG_DIR
mkdir -p $DB_DIR

chmod 777 $DATA_DIR
chmod 777 $CONFIG_DIR
chmod 777 $DB_DIR

# Crear pod
podman pod create --name $POD_NAME -p $PORT:80

# Crear contenedor de PostgreSQL
podman container run -d \
    --pod $POD_NAME \
    --name nextcloud_db \
    -e POSTGRES_USER=$POSTGRES_USER \
    -e POSTGRES_PASSWORD=$POSTGRES_PASS \
    -e POSTGRES_DB="nextcloud_db" \
    -v $DB_DIR:/var/lib/postgresql/data \
    postgres

# Crear contenedor de Redis
podman container run -d \
    --pod $POD_NAME \
    --name nextcloud_redis \
    redis

# Crear contenedor de Nextcloud con los volúmenes montados
podman container run -d \
    --pod $POD_NAME \
    --name nextcloud \
    -v $DATA_DIR:/var/www/html/data \
    -v $CONFIG_DIR:/var/www/html/config \
    -e POSTGRES_HOST="127.0.0.1" \
    -e POSTGRES_DB="nextcloud_db" \
    -e POSTGRES_USER=$POSTGRES_USER \
    -e POSTGRES_PASSWORD=$POSTGRES_PASS \
    -e NEXTCLOUD_ADMIN_USER=$NEXTCLOUD_ADMIN_USER \
    -e NEXTCLOUD_ADMIN_PASSWORD=$NEXTCLOUD_ADMIN_PASSWORD \
    -e NEXTCLOUD_TRUSTED_DOMAINS=$(hostname -I | awk '{print $1}') \
    -e REDIS_HOST="127.0.0.1" \
    nextcloud

# Abrir el puerto en el firewall
firewall-cmd --add-port=$PORT/tcp --permanent
firewall-cmd --reload

# Crear el script de inicio del pod
cat << 'EOF' > /usr/local/bin/start_nextcloud_pod.sh
#!/bin/bash

POSTGRES_PASS="Pil20000"
POSTGRES_USER="nextcloud"
NEXTCLOUD_ADMIN_USER="pilevante"
NEXTCLOUD_ADMIN_PASSWORD="Pil20000"
PORT="9999"
DATA_DIR="/mnt/nc/data"
CONFIG_DIR="/mnt/nc/config"
DB_DIR="/mnt/nc/db"
POD_NAME="nc"

# Crear directorios para los volúmenes persistentes si no existen
mkdir -p $DATA_DIR
mkdir -p $CONFIG_DIR
mkdir -p $DB_DIR

chmod 777 $DATA_DIR
chmod 777 $CONFIG_DIR
chmod 777 $DB_DIR

# Crear pod
podman pod create --name $POD_NAME -p $PORT:80

# Crear contenedor de PostgreSQL
podman container run -d \
    --pod $POD_NAME \
    --name nextcloud_db \
    -e POSTGRES_USER=$POSTGRES_USER \
    -e POSTGRES_PASSWORD=$POSTGRES_PASS \
    -e POSTGRES_DB="nextcloud_db" \
    -v $DB_DIR:/var/lib/postgresql/data \
    postgres

# Crear contenedor de Redis
podman container run -d \
    --pod $POD_NAME \
    --name nextcloud_redis \
    redis

# Crear contenedor de Nextcloud con los volúmenes montados
podman container run -d \
    --pod $POD_NAME \
    --name nextcloud \
    -v $DATA_DIR:/var/www/html/data \
    -v $CONFIG_DIR:/var/www/html/config \
    -e POSTGRES_HOST="127.0.0.1" \
    -e POSTGRES_DB="nextcloud_db" \
    -e POSTGRES_USER=$POSTGRES_USER \
    -e POSTGRES_PASSWORD=$POSTGRES_PASS \
    -e NEXTCLOUD_ADMIN_USER=$NEXTCLOUD_ADMIN_USER \
    -e NEXTCLOUD_ADMIN_PASSWORD=$NEXTCLOUD_ADMIN_PASSWORD \
    -e NEXTCLOUD_TRUSTED_DOMAINS=$(hostname -I | awk '{print $1}') \
    -e REDIS_HOST="127.0.0.1" \
    nextcloud
EOF

# Dar permisos ejecutables al script de inicio
chmod +x /usr/local/bin/start_nextcloud_pod.sh

# Crear el archivo de servicio systemd
cat << EOF > /etc/systemd/system/nextcloud-pod.service
[Unit]
Description=Nextcloud Pod
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/start_nextcloud_pod.sh
ExecStop=/usr/bin/podman pod stop nc
ExecReload=/usr/bin/podman pod restart nc
Restart=always
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOF

# Recargar los servicios de systemd
systemctl daemon-reload

# Habilitar el servicio para que se inicie automáticamente al arrancar el sistema
systemctl enable nextcloud-pod.service

# Iniciar el servicio manualmente por primera vez
systemctl start nextcloud-pod.service

echo "Nextcloud Pod configurado e iniciado con éxito."
