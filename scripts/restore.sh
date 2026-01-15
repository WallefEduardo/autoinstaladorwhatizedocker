#!/bin/bash
#
# Restore - Restaura backup do Whatize
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/manifest.sh"

print_banner

# Carregar configurações
if [ -f "${SCRIPT_DIR}/../docker/.env" ]; then
    source "${SCRIPT_DIR}/../docker/.env"
fi

print_step "Restauração do Sistema Whatize"

# ===========================================
# VERIFICAR ARGUMENTOS
# ===========================================
if [ -z "$1" ]; then
    print_error "Uso: $0 <arquivo_backup.tar.gz>"
    echo
    echo "Backups disponíveis:"
    ls -lh /root/backups/whatize/*.tar.gz 2>/dev/null || echo "  Nenhum backup encontrado"
    exit 1
fi

BACKUP_FILE="$1"

if [ ! -f "$BACKUP_FILE" ]; then
    print_error "Arquivo não encontrado: $BACKUP_FILE"
    exit 1
fi

# ===========================================
# CONFIRMAR RESTAURAÇÃO
# ===========================================
echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║                    ATENÇÃO!                                   ║${NC}"
echo -e "${RED}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${RED}║  A restauração irá SOBRESCREVER os dados atuais!             ║${NC}"
echo -e "${RED}║  Esta ação não pode ser desfeita.                            ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
echo

if ! confirm_menu "Deseja continuar com a restauração?" "n"; then
    print_info "Restauração cancelada"
    exit 0
fi

# ===========================================
# EXTRAIR BACKUP
# ===========================================
print_step "Extraindo backup"

TEMP_DIR=$(mktemp -d)
tar xzf "$BACKUP_FILE" -C "$TEMP_DIR"

# Encontrar diretório do backup
BACKUP_DIR=$(ls "$TEMP_DIR" | head -1)
RESTORE_PATH="${TEMP_DIR}/${BACKUP_DIR}"

print_success "Backup extraído em: $RESTORE_PATH"

# ===========================================
# PARAR CONTAINERS
# ===========================================
print_step "Parando containers"

cd "${SCRIPT_DIR}/../docker"
docker compose -f docker-compose.master.yml stop || true

# ===========================================
# RESTAURAR POSTGRESQL PRINCIPAL
# ===========================================
if [ -f "${RESTORE_PATH}/postgres_main.sql.gz" ]; then
    print_step "Restaurando PostgreSQL Principal"

    docker compose -f docker-compose.master.yml start postgres
    sleep 5

    print_substep "Recriando banco..."
    docker exec whatize_postgres psql -U "${DB_USER:-whatize}" -c "DROP DATABASE IF EXISTS ${DB_NAME:-whatize}" postgres 2>/dev/null || true
    docker exec whatize_postgres psql -U "${DB_USER:-whatize}" -c "CREATE DATABASE ${DB_NAME:-whatize}" postgres

    print_substep "Importando dados..."
    gunzip -c "${RESTORE_PATH}/postgres_main.sql.gz" | docker exec -i whatize_postgres psql -U "${DB_USER:-whatize}" "${DB_NAME:-whatize}"

    print_success "PostgreSQL principal restaurado"
fi

# ===========================================
# RESTAURAR POSTGRESQL LOOKUP
# ===========================================
if [ -f "${RESTORE_PATH}/postgres_lookup.sql.gz" ]; then
    print_step "Restaurando PostgreSQL Lookup"

    docker compose -f docker-compose.master.yml start postgres-lookup
    sleep 5

    print_substep "Recriando banco..."
    docker exec whatize_postgres_lookup psql -U lookup_user -c "DROP DATABASE IF EXISTS lookup_service" postgres 2>/dev/null || true
    docker exec whatize_postgres_lookup psql -U lookup_user -c "CREATE DATABASE lookup_service" postgres

    print_substep "Importando dados..."
    gunzip -c "${RESTORE_PATH}/postgres_lookup.sql.gz" | docker exec -i whatize_postgres_lookup psql -U lookup_user lookup_service

    print_success "PostgreSQL lookup restaurado"
fi

# ===========================================
# RESTAURAR REDIS
# ===========================================
if [ -f "${RESTORE_PATH}/redis_main.rdb" ]; then
    print_step "Restaurando Redis Principal"

    docker compose -f docker-compose.master.yml stop redis
    docker cp "${RESTORE_PATH}/redis_main.rdb" whatize_redis:/data/dump.rdb 2>/dev/null || true
    docker compose -f docker-compose.master.yml start redis

    print_success "Redis principal restaurado"
fi

if [ -f "${RESTORE_PATH}/redis_baileys.rdb" ]; then
    print_step "Restaurando Redis Baileys"

    docker compose -f docker-compose.master.yml stop redis-baileys
    docker cp "${RESTORE_PATH}/redis_baileys.rdb" whatize_redis_baileys:/data/dump.rdb 2>/dev/null || true
    docker compose -f docker-compose.master.yml start redis-baileys

    print_success "Redis baileys restaurado"
fi

# ===========================================
# RESTAURAR ARQUIVOS PÚBLICOS
# ===========================================
if [ -f "${RESTORE_PATH}/public_files.tar.gz" ]; then
    print_step "Restaurando Arquivos Públicos"

    WHATIZE_PATH="${WHATIZE_PATH:-/home/deploy/whatize}"
    PUBLIC_DIR="${WHATIZE_PATH}/backend/public"

    if [ -d "$PUBLIC_DIR" ]; then
        tar xzf "${RESTORE_PATH}/public_files.tar.gz" -C "$PUBLIC_DIR"
        print_success "Arquivos públicos restaurados"
    else
        print_warning "Diretório público não encontrado: $PUBLIC_DIR"
    fi
fi

# ===========================================
# RESTAURAR VOLUMES
# ===========================================
print_step "Restaurando Volumes Docker"

for volume_file in "${RESTORE_PATH}"/autoinstaladordocker_*.tar.gz; do
    if [ -f "$volume_file" ]; then
        volume_name=$(basename "$volume_file" .tar.gz)
        print_substep "Restaurando volume: $volume_name"

        docker run --rm -v "${volume_name}:/data" -v "${RESTORE_PATH}:/backup" alpine \
            sh -c "rm -rf /data/* && tar xzf /backup/$(basename $volume_file) -C /data" 2>/dev/null || true
    fi
done

# ===========================================
# REINICIAR CONTAINERS
# ===========================================
print_step "Reiniciando containers"

docker compose -f docker-compose.master.yml up -d

print_substep "Aguardando containers ficarem saudáveis..."
sleep 30

# ===========================================
# LIMPEZA
# ===========================================
rm -rf "$TEMP_DIR"

# ===========================================
# FINALIZAÇÃO
# ===========================================
print_step "Verificando status"

docker compose -f docker-compose.master.yml ps

echo
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║               RESTAURAÇÃO CONCLUÍDA!                          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${WHITE}Verifique os logs:${NC}"
echo -e "  ${CYAN}docker compose -f ${SCRIPT_DIR}/../docker/docker-compose.master.yml logs -f${NC}"
echo
