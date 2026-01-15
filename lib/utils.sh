#!/bin/bash
#
# Funções utilitárias
#

# Gerar senha aleatória
generate_password() {
    local length=${1:-32}
    openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c "$length"
}

# Gerar chave secreta
generate_secret() {
    openssl rand -hex 32
}

# Verificar se comando existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Verificar se porta está em uso
port_in_use() {
    local port=$1
    if command_exists ss; then
        ss -tuln | grep -q ":${port} "
    elif command_exists netstat; then
        netstat -tuln | grep -q ":${port} "
    else
        # Fallback usando /dev/tcp
        (echo >/dev/tcp/localhost/$port) 2>/dev/null && return 0 || return 1
    fi
}

# Encontrar próxima porta disponível
find_available_port() {
    local start_port=${1:-3000}
    local port=$start_port
    while port_in_use $port; do
        ((port++))
        if [ $port -gt 65535 ]; then
            echo ""
            return 1
        fi
    done
    echo $port
}

# Verificar se é root
check_root() {
    if [ "$(id -u)" != "0" ]; then
        print_error "Este script deve ser executado como root"
        exit 1
    fi
}

# Verificar sistema operacional
check_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        print_error "Sistema operacional não suportado"
        exit 1
    fi

    case $OS in
        ubuntu|debian)
            print_info "Sistema detectado: $OS $VERSION"
            ;;
        *)
            print_warning "Sistema $OS pode não ser totalmente suportado"
            ;;
    esac
}

# Verificar memória disponível
check_memory() {
    local min_memory=${1:-2048}  # MB
    local total_memory=$(free -m | awk '/^Mem:/{print $2}')

    if [ "$total_memory" -lt "$min_memory" ]; then
        print_warning "Memória disponível: ${total_memory}MB (recomendado: ${min_memory}MB)"
        return 1
    fi
    print_success "Memória disponível: ${total_memory}MB"
    return 0
}

# Verificar espaço em disco
check_disk_space() {
    local min_space=${1:-10}  # GB
    local available=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')

    if [ "$available" -lt "$min_space" ]; then
        print_warning "Espaço disponível: ${available}GB (recomendado: ${min_space}GB)"
        return 1
    fi
    print_success "Espaço disponível: ${available}GB"
    return 0
}

# Aguardar serviço ficar disponível
wait_for_service() {
    local host=$1
    local port=$2
    local max_attempts=${3:-30}
    local delay=${4:-2}

    print_substep "Aguardando $host:$port..."

    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        if nc -z "$host" "$port" 2>/dev/null; then
            print_success "$host:$port está disponível"
            return 0
        fi
        sleep $delay
        ((attempt++))
    done

    print_error "Timeout aguardando $host:$port"
    return 1
}

# Aguardar URL responder
wait_for_url() {
    local url=$1
    local max_attempts=${2:-30}
    local delay=${3:-2}

    print_substep "Aguardando $url..."

    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        if curl -s -o /dev/null -w "%{http_code}" "$url" | grep -q "200\|301\|302"; then
            print_success "$url está respondendo"
            return 0
        fi
        sleep $delay
        ((attempt++))
    done

    print_error "Timeout aguardando $url"
    return 1
}

# Criar usuário se não existir
create_user_if_not_exists() {
    local username=$1
    local password=$2

    if id "$username" &>/dev/null; then
        print_info "Usuário $username já existe"
        return 0
    fi

    print_substep "Criando usuário $username..."
    useradd -m -s /bin/bash "$username"
    echo "$username:$password" | chpasswd
    usermod -aG sudo "$username"
    usermod -aG docker "$username" 2>/dev/null || true
    print_success "Usuário $username criado"
}

# Fazer backup de arquivo
backup_file() {
    local file=$1
    if [ -f "$file" ]; then
        local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$file" "$backup"
        print_info "Backup criado: $backup"
    fi
}

# Substituir variável em arquivo
replace_in_file() {
    local file=$1
    local search=$2
    local replace=$3

    if [ -f "$file" ]; then
        sed -i "s|${search}|${replace}|g" "$file"
    fi
}

# Adicionar linha se não existir
add_line_if_not_exists() {
    local file=$1
    local line=$2

    if ! grep -qF "$line" "$file" 2>/dev/null; then
        echo "$line" >> "$file"
    fi
}

# Obter IP público
get_public_ip() {
    curl -s ifconfig.me 2>/dev/null || \
    curl -s icanhazip.com 2>/dev/null || \
    curl -s ipecho.net/plain 2>/dev/null || \
    echo "unknown"
}

# Obter IP local
get_local_ip() {
    hostname -I | awk '{print $1}'
}

# Confirmar ação
confirm() {
    local prompt="${1:-Deseja continuar?}"
    local default="${2:-n}"

    if [ "$default" = "y" ]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi

    read -p "$prompt" response
    response=${response:-$default}

    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

# Carregar variáveis de arquivo .env
load_env() {
    local env_file=$1
    if [ -f "$env_file" ]; then
        export $(grep -v '^#' "$env_file" | xargs)
    fi
}

# Salvar variável em arquivo .env
save_env() {
    local env_file=$1
    local key=$2
    local value=$3

    if grep -q "^${key}=" "$env_file" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$env_file"
    else
        echo "${key}=${value}" >> "$env_file"
    fi
}
