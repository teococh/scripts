#!/bin/bash

# Definir variables predeterminadas
POSTGRES_PASS="Pil20000"
NEXTCLOUD_ADMIN_USER="pilevante"
NEXTCLOUD_ADMIN_PASSWORD="Pil20000"
PORT="9999"
DATA_DIR="/mnt/nc"
VOLUME_DIR="/var/www/html/data"
POD_NAME="nc"

# Función de ayuda
function show_help {
    echo "Uso: $0 [-p PASSWORD] [-u USER] [-a ADMIN_USER] [-b ADMIN_PASSWORD] [-d DATA_DIR] [-v VOLUME_DIR] [-o PORT] [-n POD_NAME]"
    echo "Options:"
    echo "  -p  Contraseña para la base de datos PostgreSQL (por defecto: Pil20000)"
    echo "  -u  Usuario para la base de datos PostgreSQL (por defecto: nextcloud)"
    echo "  -a  Usuario administrador de Nextcloud (por defecto: pilevante)"
    echo "  -b  Contraseña del usuario administrador de Nextcloud (por defecto: Pil20000)"
    echo "  -d  Directorio donde se almacenarán los datos de Nextcloud (por defecto: /mnt/nc)"
    echo "  -v  Directorio dentro del contenedor donde se montarán los datos de Nextcloud (por defecto: /var/www/html/data)"
    echo "  -o  Puerto para exponer Nextcloud (por defecto: 9999)"
    echo "  -n  Nombre del pod (por defecto: nc)"
    exit 1
}

# Parsear opciones
while getopts ":p:u:a:b:d:v:o:n:h" opt; do
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
        v )
            VOLUME_DIR=$OPTARG
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

# Crear pod
podman pod create --name $POD_NAME -p $PORT:80

# Crear contenedor de PostgreSQL
podman container run -d \
    --pod $POD_NAME \
    --name nextcloud_db \
    -e POSTGRES_USER="$POSTGRES_USER" \
    -e POSTGRES_PASSWORD=$POSTGRES_PASS \
    postgres

# Crear contenedor de Redis
podman container run -d \
    --pod $POD_NAME \
    --name Nextcloud_redis \
    redis

# Crear directorio para los datos de Nextcloud si no existe
mkdir -p $DATA_DIR

# Crear contenedor de Nextcloud con el volumen montado
podman container run -d \
    --pod $POD_NAME \
    --name nextcloud \
    -v $DATA_DIR:$VOLUME_DIR \  # Montar el volumen
    -e POSTGRES_HOST="127.0.0.1" \
    -e POSTGRES_DB="nextcloud" \
    -e POSTGRES_USER="nextcloud" \
    -e POSTGRES_PASSWORD=$POSTGRES_PASS \
    -e NEXTCLOUD_ADMIN_USER=$NEXTCLOUD_ADMIN_USER \
    -e NEXTCLOUD_ADMIN_PASSWORD=$NEXTCLOUD_ADMIN_PASSWORD \
    -e NEXTCLOUD_TRUSTED_DOMAINS=$(hostname -I | awk '{print $1}') \
    -e REDIS_HOST="127.0.0.1" \
    nextcloud

# Abrir el puerto en el firewall
firewall-cmd --add-port=$PORT/tcp --permanent
firewall-cmd --reload
