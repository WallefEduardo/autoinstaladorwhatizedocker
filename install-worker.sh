#!/bin/bash
#
# Instalador Worker - Instala VPS Worker para instâncias adicionais
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/manifest.sh"

print_banner

# Verificar root
if [ "$(id -u)" != "0" ]; then
    print_error "Execute como root: sudo $0"
    exit 1
fi

validate_system_requirements

# ===========================================
# COLETAR INFORMAÇÕES
# ===========================================
while true; do
    if collect_worker_info; then
        break
    fi
done

# ===========================================
# CONFIGURAR SISTEMA
# ===========================================
export DEPLOY_USER="${DEPLOY_USER:-deploy}"
export DEPLOY_PASS="${DEPLOY_PASS}"

"${SCRIPT_DIR}/scripts/setup-system.sh"

# ===========================================
# CRIAR ARQUIVO .ENV
# ===========================================
print_step "Criando configuração"

ENV_FILE="${SCRIPT_DIR}/docker/.env"

cat > "$ENV_FILE" << EOF
# WHATIZE Worker - Gerado em $(date)
VERSION=latest
WORKER_NAME=${WORKER_NAME}
WORKER_DOMAIN=${WORKER_DOMAIN}
MASTER_HOST=${MASTER_HOST}
MASTER_LOOKUP_PORT=${MASTER_LOOKUP_PORT}
LOOKUP_API_KEY=${LOOKUP_API_KEY}
REDIS_PASS=${REDIS_PASS}
REDIS_PORT=6379
SSL_EMAIL=${SSL_EMAIL}
DEPLOY_USER=${DEPLOY_USER}
EOF

chmod 600 "$ENV_FILE"

# ===========================================
# CRIAR REDE E SUBIR REDIS
# ===========================================
print_step "Iniciando infraestrutura"

docker_create_network "whatize_net" "172.28.0.0/16"

cd "${SCRIPT_DIR}/docker"
docker compose -f docker-compose.worker.yml up -d

# ===========================================
# GERAR CHAVE SSH
# ===========================================
print_step "Configurando acesso SSH"

SSH_KEY_PATH="/home/${DEPLOY_USER}/.ssh/whatize_worker_key"
generate_ssh_keys "$SSH_KEY_PATH" "whatize-worker-${WORKER_NAME}"

# Copiar para root também
mkdir -p /root/.ssh
cp "$SSH_KEY_PATH" /root/.ssh/
cp "${SSH_KEY_PATH}.pub" /root/.ssh/
chmod 600 /root/.ssh/whatize_worker_key

# ===========================================
# FINALIZAÇÃO
# ===========================================
print_step "Worker Instalado!"

echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              WORKER INSTALADO COM SUCESSO!                    ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${WHITE}Próximo passo - No Master, execute:${NC}"
echo
echo -e "${CYAN}./register-worker.sh \\${NC}"
echo -e "${CYAN}  --host $(get_public_ip) \\${NC}"
echo -e "${CYAN}  --name \"${WORKER_NAME}\" \\${NC}"
echo -e "${CYAN}  --ssh-user ${DEPLOY_USER}${NC}"
echo
echo -e "${WHITE}Chave pública para adicionar no Master:${NC}"
cat "${SSH_KEY_PATH}.pub"
echo
