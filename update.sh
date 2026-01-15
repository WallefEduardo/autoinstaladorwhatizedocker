#!/bin/bash
#
# Script de Atualização do Whatize
#

set -e

# Obter diretório do script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Carregar bibliotecas
source "${SCRIPT_DIR}/lib/manifest.sh"

# Carregar configurações
if [ -f "${SCRIPT_DIR}/docker/.env" ]; then
    source "${SCRIPT_DIR}/docker/.env"
else
    print_error "Arquivo .env não encontrado. Execute a instalação primeiro."
    exit 1
fi

print_banner

print_step "Atualizando Whatize"

WHATIZE_PATH="${WHATIZE_PATH:-/home/deploy/whatize}"
GIT_BRANCH="${GIT_BRANCH:-main}"

# ===========================================
# VERIFICAR SE ESTÁ INSTALADO
# ===========================================
if [ ! -d "$WHATIZE_PATH" ]; then
    print_error "Instalação não encontrada em $WHATIZE_PATH"
    exit 1
fi

# ===========================================
# BACKUP ANTES DE ATUALIZAR
# ===========================================
if confirm_menu "Deseja fazer backup antes de atualizar?" "y"; then
    print_substep "Criando backup..."
    "${SCRIPT_DIR}/scripts/backup.sh" 2>/dev/null || print_warning "Backup não disponível"
fi

# ===========================================
# ATUALIZAR CÓDIGO
# ===========================================
print_step "Atualizando código fonte"

cd "$WHATIZE_PATH"

print_substep "Buscando atualizações..."
git fetch --all

print_substep "Aplicando atualizações..."
git reset --hard "origin/${GIT_BRANCH}"

# Mostrar últimos commits
print_info "Últimos commits:"
git log --oneline -5

print_success "Código atualizado"

# ===========================================
# REBUILD DAS IMAGENS
# ===========================================
print_step "Reconstruindo imagens Docker"

export WHATIZE_PATH
export VERSION="latest"

"${SCRIPT_DIR}/scripts/build-images.sh"

# ===========================================
# REINICIAR CONTAINERS
# ===========================================
print_step "Reiniciando containers"

cd "${SCRIPT_DIR}/docker"

print_substep "Parando containers..."
docker compose -f docker-compose.master.yml down

print_substep "Iniciando containers com novas imagens..."
docker compose -f docker-compose.master.yml up -d

print_substep "Aguardando containers ficarem saudáveis..."
sleep 30

# Verificar saúde
docker_health_check docker-compose.master.yml || true

# ===========================================
# VERIFICAR STATUS
# ===========================================
print_step "Status Final"

docker compose -f docker-compose.master.yml ps

print_success "Atualização concluída!"

echo
echo -e "${WHITE}Verifique os logs para confirmar que tudo está funcionando:${NC}"
echo -e "  ${CYAN}docker compose -f ${SCRIPT_DIR}/docker/docker-compose.master.yml logs -f${NC}"
echo
