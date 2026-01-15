#!/bin/bash
#
# Backup - Backup dos dados do Whatize
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/manifest.sh"

print_banner

# Carregar configurações
if [ -f "${SCRIPT_DIR}/../docker/.env" ]; then
    source "${SCRIPT_DIR}/../docker/.env"
fi

print_step "Backup do Sistema Whatize"

# ===========================================
# CONFIGURAÇÃO
# ===========================================
BACKUP_DIR="${BACKUP_DIR:-/root/backups/whatize}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME="whatize_backup_${TIMESTAMP}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

# Criar diretório de backup
mkdir -p "$BACKUP_PATH"

# ===========================================
# BACKUP DO POSTGRESQL PRINCIPAL
# ===========================================
print_step "Backup do PostgreSQL Principal"

if docker ps -q -f "name=whatize_postgres$" &>/dev/null; then
    print_substep "Exportando banco whatize..."
    docker exec whatize_postgres pg_dump -U "${DB_USER:-whatize}" "${DB_NAME:-whatize}" | gzip > "${BACKUP_PATH}/postgres_main.sql.gz"
    print_success "Backup PostgreSQL principal: postgres_main.sql.gz"
else
    print_warning "Container whatize_postgres não está rodando"
fi

# ===========================================
# BACKUP DO POSTGRESQL LOOKUP
# ===========================================
print_step "Backup do PostgreSQL Lookup"

if docker ps -q -f "name=whatize_postgres_lookup" &>/dev/null; then
    print_substep "Exportando banco lookup_service..."
    docker exec whatize_postgres_lookup pg_dump -U lookup_user lookup_service | gzip > "${BACKUP_PATH}/postgres_lookup.sql.gz"
    print_success "Backup PostgreSQL lookup: postgres_lookup.sql.gz"
else
    print_warning "Container whatize_postgres_lookup não está rodando"
fi

# ===========================================
# BACKUP DO REDIS
# ===========================================
print_step "Backup do Redis"

if docker ps -q -f "name=whatize_redis$" &>/dev/null; then
    print_substep "Salvando dados do Redis..."
    docker exec whatize_redis redis-cli -a "${REDIS_PASS}" BGSAVE &>/dev/null || true
    sleep 2
    docker cp whatize_redis:/data/dump.rdb "${BACKUP_PATH}/redis_main.rdb" 2>/dev/null || print_warning "RDB não disponível"
    print_success "Backup Redis principal: redis_main.rdb"
else
    print_warning "Container whatize_redis não está rodando"
fi

if docker ps -q -f "name=whatize_redis_baileys" &>/dev/null; then
    print_substep "Salvando dados do Redis Baileys..."
    docker exec whatize_redis_baileys redis-cli BGSAVE &>/dev/null || true
    sleep 2
    docker cp whatize_redis_baileys:/data/dump.rdb "${BACKUP_PATH}/redis_baileys.rdb" 2>/dev/null || print_warning "RDB não disponível"
    print_success "Backup Redis Baileys: redis_baileys.rdb"
else
    print_warning "Container whatize_redis_baileys não está rodando"
fi

# ===========================================
# BACKUP DOS VOLUMES DOCKER
# ===========================================
print_step "Backup dos Volumes"

# Lista de volumes para backup
VOLUMES=(
    "autoinstaladordocker_backend_public"
    "autoinstaladordocker_backend_logs"
)

for volume in "${VOLUMES[@]}"; do
    if docker volume inspect "$volume" &>/dev/null; then
        print_substep "Backup volume: $volume"
        docker run --rm -v "${volume}:/data" -v "${BACKUP_PATH}:/backup" alpine \
            tar czf "/backup/${volume}.tar.gz" -C /data . 2>/dev/null || true
    fi
done

# ===========================================
# BACKUP DO ARQUIVO .ENV
# ===========================================
print_step "Backup das Configurações"

if [ -f "${SCRIPT_DIR}/../docker/.env" ]; then
    cp "${SCRIPT_DIR}/../docker/.env" "${BACKUP_PATH}/env_backup"
    print_success "Arquivo .env copiado"
fi

# ===========================================
# BACKUP DOS ARQUIVOS PÚBLICOS
# ===========================================
print_step "Backup dos Arquivos Públicos"

WHATIZE_PATH="${WHATIZE_PATH:-/home/deploy/whatize}"
PUBLIC_DIR="${WHATIZE_PATH}/backend/public"

if [ -d "$PUBLIC_DIR" ]; then
    print_substep "Compactando arquivos públicos..."
    tar czf "${BACKUP_PATH}/public_files.tar.gz" -C "$PUBLIC_DIR" . 2>/dev/null || true
    print_success "Arquivos públicos: public_files.tar.gz"
else
    print_warning "Diretório público não encontrado: $PUBLIC_DIR"
fi

# ===========================================
# CRIAR ARQUIVO FINAL
# ===========================================
print_step "Finalizando Backup"

cd "$BACKUP_DIR"
tar czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME"
rm -rf "$BACKUP_NAME"

FINAL_SIZE=$(du -h "${BACKUP_NAME}.tar.gz" | cut -f1)

print_success "Backup completo!"

echo
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    BACKUP CONCLUÍDO!                          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${WHITE}Arquivo:${NC} ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
echo -e "${WHITE}Tamanho:${NC} ${FINAL_SIZE}"
echo
echo -e "${WHITE}Para restaurar:${NC}"
echo -e "  ${CYAN}./scripts/restore.sh ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz${NC}"
echo

# ===========================================
# LIMPEZA DE BACKUPS ANTIGOS
# ===========================================
MAX_BACKUPS="${MAX_BACKUPS:-7}"
BACKUP_COUNT=$(ls -1 "${BACKUP_DIR}"/*.tar.gz 2>/dev/null | wc -l)

if [ "$BACKUP_COUNT" -gt "$MAX_BACKUPS" ]; then
    print_info "Removendo backups antigos (mantendo últimos $MAX_BACKUPS)..."
    ls -1t "${BACKUP_DIR}"/*.tar.gz | tail -n +$((MAX_BACKUPS + 1)) | xargs rm -f
fi
