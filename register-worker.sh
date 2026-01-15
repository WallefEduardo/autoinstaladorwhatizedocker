#!/bin/bash
#
# Register Worker - Registra VPS Worker no Master
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

# ===========================================
# PARSE ARGUMENTOS
# ===========================================
WORKER_HOST=""
WORKER_NAME=""
WORKER_SSH_USER="deploy"
WORKER_SSH_PORT="22"
WORKER_MAX_INSTANCES="10"

usage() {
    echo "Uso: $0 [OPTIONS]"
    echo
    echo "Opções:"
    echo "  --host HOST          IP ou domínio do Worker (obrigatório)"
    echo "  --name NAME          Nome do Worker (obrigatório)"
    echo "  --ssh-user USER      Usuário SSH (padrão: deploy)"
    echo "  --ssh-port PORT      Porta SSH (padrão: 22)"
    echo "  --max-instances N    Máximo de instâncias (padrão: 10)"
    echo "  -h, --help           Exibe esta ajuda"
    echo
    echo "Exemplo:"
    echo "  $0 --host worker1.example.com --name \"Worker 1\""
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --host)
            WORKER_HOST="$2"
            shift 2
            ;;
        --name)
            WORKER_NAME="$2"
            shift 2
            ;;
        --ssh-user)
            WORKER_SSH_USER="$2"
            shift 2
            ;;
        --ssh-port)
            WORKER_SSH_PORT="$2"
            shift 2
            ;;
        --max-instances)
            WORKER_MAX_INSTANCES="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            print_error "Opção desconhecida: $1"
            usage
            ;;
    esac
done

# Validar argumentos obrigatórios
if [ -z "$WORKER_HOST" ]; then
    print_error "Host do Worker é obrigatório (--host)"
    usage
fi

if [ -z "$WORKER_NAME" ]; then
    print_error "Nome do Worker é obrigatório (--name)"
    usage
fi

# ===========================================
# CARREGAR CONFIGURAÇÕES
# ===========================================
if [ -f "${SCRIPT_DIR}/docker/.env" ]; then
    source "${SCRIPT_DIR}/docker/.env"
else
    print_error "Arquivo .env não encontrado. Execute install-master.sh primeiro."
    exit 1
fi

# ===========================================
# TESTAR CONEXÃO SSH
# ===========================================
print_step "Testando conexão SSH"

SSH_KEY_PATH="${SSH_KEY_PATH:-/home/deploy/.ssh/whatize_master_key}"

if [ ! -f "$SSH_KEY_PATH" ]; then
    print_error "Chave SSH não encontrada em $SSH_KEY_PATH"
    echo
    echo -e "${YELLOW}A chave pública do Worker deve ser adicionada ao Master.${NC}"
    echo -e "${YELLOW}No Worker, execute: cat /home/deploy/.ssh/whatize_worker_key.pub${NC}"
    echo -e "${YELLOW}Depois adicione essa chave em: /home/deploy/.ssh/authorized_keys${NC}"
    exit 1
fi

print_substep "Testando conexão com ${WORKER_HOST}..."

if ! ssh -i "$SSH_KEY_PATH" -p "$WORKER_SSH_PORT" -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
    "${WORKER_SSH_USER}@${WORKER_HOST}" "echo 'Conexão OK'" 2>/dev/null; then
    print_error "Não foi possível conectar ao Worker"
    echo
    echo -e "${YELLOW}Verifique:${NC}"
    echo "  1. O Worker está acessível: ping ${WORKER_HOST}"
    echo "  2. A porta SSH está aberta: nc -zv ${WORKER_HOST} ${WORKER_SSH_PORT}"
    echo "  3. A chave SSH está configurada corretamente"
    exit 1
fi

print_success "Conexão SSH estabelecida"

# ===========================================
# VERIFICAR DOCKER NO WORKER
# ===========================================
print_step "Verificando Docker no Worker"

if ! ssh -i "$SSH_KEY_PATH" -p "$WORKER_SSH_PORT" \
    "${WORKER_SSH_USER}@${WORKER_HOST}" "docker --version" &>/dev/null; then
    print_error "Docker não encontrado no Worker"
    echo
    echo -e "${YELLOW}Execute install-worker.sh no Worker primeiro.${NC}"
    exit 1
fi

print_success "Docker está instalado no Worker"

# ===========================================
# VERIFICAR REDIS NO WORKER
# ===========================================
print_step "Verificando Redis no Worker"

REDIS_STATUS=$(ssh -i "$SSH_KEY_PATH" -p "$WORKER_SSH_PORT" \
    "${WORKER_SSH_USER}@${WORKER_HOST}" "docker ps --filter 'name=whatize_redis' --format '{{.Status}}'" 2>/dev/null || echo "")

if [ -z "$REDIS_STATUS" ]; then
    print_warning "Redis não está rodando no Worker"
    echo
    if confirm_menu "Deseja iniciar o Redis no Worker?" "y"; then
        ssh -i "$SSH_KEY_PATH" -p "$WORKER_SSH_PORT" \
            "${WORKER_SSH_USER}@${WORKER_HOST}" \
            "cd /root/AutoInstaladorWhatizeDocker/docker && docker compose -f docker-compose.worker.yml up -d"
        print_success "Redis iniciado"
    else
        print_warning "Continuando sem Redis ativo"
    fi
else
    print_success "Redis está rodando: $REDIS_STATUS"
fi

# ===========================================
# REGISTRAR NO BANCO DO LOOKUP
# ===========================================
print_step "Registrando Worker no Lookup Service"

# Verificar se já existe
EXISTING=$(docker exec whatize_postgres_lookup psql -U lookup_user -d lookup_service -t -c \
    "SELECT id FROM vps_servers WHERE host = '${WORKER_HOST}'" 2>/dev/null | tr -d ' ')

if [ -n "$EXISTING" ] && [ "$EXISTING" != "" ]; then
    print_warning "Worker já registrado com ID: $EXISTING"
    if confirm_menu "Deseja atualizar o registro existente?" "y"; then
        docker exec whatize_postgres_lookup psql -U lookup_user -d lookup_service -c \
            "UPDATE vps_servers SET
                name = '${WORKER_NAME}',
                ssh_port = ${WORKER_SSH_PORT},
                ssh_user = '${WORKER_SSH_USER}',
                ssh_key_path = '${SSH_KEY_PATH}',
                max_instances = ${WORKER_MAX_INSTANCES},
                is_active = true,
                updated_at = NOW()
            WHERE host = '${WORKER_HOST}'"
        print_success "Registro atualizado"
    fi
else
    # Inserir novo registro
    docker exec whatize_postgres_lookup psql -U lookup_user -d lookup_service -c \
        "INSERT INTO vps_servers (name, host, ssh_port, ssh_user, ssh_key_path, docker_port, is_master, is_active, max_instances)
         VALUES ('${WORKER_NAME}', '${WORKER_HOST}', ${WORKER_SSH_PORT}, '${WORKER_SSH_USER}', '${SSH_KEY_PATH}', 2375, false, true, ${WORKER_MAX_INSTANCES})"
    print_success "Worker registrado com sucesso"
fi

# ===========================================
# COPIAR CHAVE SSH PARA O MASTER
# ===========================================
print_step "Configurando acesso SSH do Master ao Worker"

# Obter chave pública do Worker
WORKER_PUB_KEY=$(ssh -i "$SSH_KEY_PATH" -p "$WORKER_SSH_PORT" \
    "${WORKER_SSH_USER}@${WORKER_HOST}" "cat ~/.ssh/whatize_worker_key.pub 2>/dev/null || cat ~/.ssh/id_rsa.pub 2>/dev/null" || echo "")

if [ -n "$WORKER_PUB_KEY" ]; then
    # Adicionar ao authorized_keys do Master (para comunicação reversa se necessário)
    MASTER_AUTH_KEYS="/home/deploy/.ssh/authorized_keys"
    if ! grep -q "${WORKER_PUB_KEY}" "$MASTER_AUTH_KEYS" 2>/dev/null; then
        echo "$WORKER_PUB_KEY" >> "$MASTER_AUTH_KEYS"
        print_success "Chave do Worker adicionada ao Master"
    else
        print_info "Chave já existe no authorized_keys"
    fi
fi

# ===========================================
# EXIBIR RESUMO
# ===========================================
print_step "Worker Registrado!"

echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              WORKER REGISTRADO COM SUCESSO!                   ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${WHITE}Detalhes do Worker:${NC}"
echo -e "  Nome:          ${CYAN}${WORKER_NAME}${NC}"
echo -e "  Host:          ${CYAN}${WORKER_HOST}${NC}"
echo -e "  SSH User:      ${CYAN}${WORKER_SSH_USER}${NC}"
echo -e "  SSH Port:      ${CYAN}${WORKER_SSH_PORT}${NC}"
echo -e "  Max Instâncias: ${CYAN}${WORKER_MAX_INSTANCES}${NC}"
echo
echo -e "${WHITE}Próximos passos:${NC}"
echo "  1. Acesse o painel: ${FRONTEND_URL}/super-admin/instances"
echo "  2. Clique em 'Nova Instância'"
echo "  3. Selecione o Worker '${WORKER_NAME}' como destino"
echo
