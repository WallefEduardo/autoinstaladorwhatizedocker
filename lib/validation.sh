#!/bin/bash
#
# Funções de validação
#

# Validar domínio
validate_domain() {
    local domain=$1
    local regex='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'

    if [[ $domain =~ $regex ]]; then
        return 0
    else
        return 1
    fi
}

# Validar IP
validate_ip() {
    local ip=$1
    local regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'

    if [[ $ip =~ $regex ]]; then
        # Verificar cada octeto
        IFS='.' read -ra octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if [ "$octet" -lt 0 ] || [ "$octet" -gt 255 ]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# Validar email
validate_email() {
    local email=$1
    local regex='^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'

    if [[ $email =~ $regex ]]; then
        return 0
    fi
    return 1
}

# Validar porta
validate_port() {
    local port=$1

    if [[ $port =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        return 0
    fi
    return 1
}

# Validar código de instância
validate_instance_code() {
    local code=$1
    local regex='^[A-Z0-9]{3,10}$'

    # Converter para maiúsculas
    code=$(echo "$code" | tr '[:lower:]' '[:upper:]')

    if [[ $code =~ $regex ]]; then
        return 0
    fi
    return 1
}

# Validar URL
validate_url() {
    local url=$1
    local regex='^https?://[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*(/.*)?$'

    if [[ $url =~ $regex ]]; then
        return 0
    fi
    return 1
}

# Validar senha forte
validate_password_strength() {
    local password=$1
    local min_length=${2:-8}

    # Verificar comprimento mínimo
    if [ ${#password} -lt $min_length ]; then
        echo "Senha deve ter pelo menos $min_length caracteres"
        return 1
    fi

    # Verificar se tem letra maiúscula
    if ! [[ $password =~ [A-Z] ]]; then
        echo "Senha deve conter pelo menos uma letra maiúscula"
        return 1
    fi

    # Verificar se tem letra minúscula
    if ! [[ $password =~ [a-z] ]]; then
        echo "Senha deve conter pelo menos uma letra minúscula"
        return 1
    fi

    # Verificar se tem número
    if ! [[ $password =~ [0-9] ]]; then
        echo "Senha deve conter pelo menos um número"
        return 1
    fi

    return 0
}

# Validar DNS do domínio
validate_dns() {
    local domain=$1
    local expected_ip=$2

    local resolved_ip=$(dig +short "$domain" | tail -1)

    if [ -z "$resolved_ip" ]; then
        print_warning "DNS não configurado para $domain"
        return 1
    fi

    if [ -n "$expected_ip" ] && [ "$resolved_ip" != "$expected_ip" ]; then
        print_warning "DNS de $domain aponta para $resolved_ip (esperado: $expected_ip)"
        return 1
    fi

    print_success "DNS de $domain: $resolved_ip"
    return 0
}

# Verificar conectividade com host remoto
validate_ssh_connection() {
    local host=$1
    local port=${2:-22}
    local user=${3:-deploy}
    local key_path=$4

    local ssh_opts="-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no"

    if [ -n "$key_path" ] && [ -f "$key_path" ]; then
        ssh_opts="$ssh_opts -i $key_path"
    fi

    if ssh $ssh_opts -p "$port" "${user}@${host}" "echo ok" &>/dev/null; then
        print_success "Conexão SSH com $host OK"
        return 0
    else
        print_error "Falha na conexão SSH com $host"
        return 1
    fi
}

# Verificar se Docker está instalado e funcionando
validate_docker() {
    if ! command_exists docker; then
        print_error "Docker não está instalado"
        return 1
    fi

    if ! docker info &>/dev/null; then
        print_error "Docker daemon não está rodando"
        return 1
    fi

    print_success "Docker está funcionando"
    return 0
}

# Verificar se Docker Compose está instalado
validate_docker_compose() {
    if docker compose version &>/dev/null; then
        print_success "Docker Compose (plugin) está instalado"
        return 0
    elif command_exists docker-compose; then
        print_success "Docker Compose (standalone) está instalado"
        return 0
    else
        print_error "Docker Compose não está instalado"
        return 1
    fi
}

# Verificar requisitos mínimos do sistema
validate_system_requirements() {
    print_step "Verificando requisitos do sistema"

    local errors=0

    # Verificar se é root
    if [ "$(id -u)" != "0" ]; then
        print_error "Execute como root"
        ((errors++))
    else
        print_success "Executando como root"
    fi

    # Verificar memória
    check_memory 2048 || ((errors++))

    # Verificar disco
    check_disk_space 10 || ((errors++))

    # Verificar sistema operacional
    check_os

    return $errors
}

# Validar configuração do .env
validate_env_config() {
    local env_file=$1
    local required_vars=("$@")

    # Remover primeiro argumento (env_file)
    unset required_vars[0]

    if [ ! -f "$env_file" ]; then
        print_error "Arquivo $env_file não encontrado"
        return 1
    fi

    local missing=0
    for var in "${required_vars[@]}"; do
        if ! grep -q "^${var}=" "$env_file"; then
            print_error "Variável $var não definida em $env_file"
            ((missing++))
        fi
    done

    return $missing
}
