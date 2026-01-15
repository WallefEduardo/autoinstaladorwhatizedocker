#!/bin/bash
#
# Funções SSH para Multi-VPS
#

# Opções padrão do SSH
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=30 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Gerar par de chaves SSH
generate_ssh_keys() {
    local key_path=${1:-"$HOME/.ssh/whatize_deploy_key"}
    local key_name=${2:-"whatize-deploy"}

    if [ -f "$key_path" ]; then
        print_info "Chave SSH já existe em $key_path"
        return 0
    fi

    print_substep "Gerando par de chaves SSH..."
    mkdir -p "$(dirname "$key_path")"
    ssh-keygen -t ed25519 -f "$key_path" -N "" -C "$key_name"
    chmod 600 "$key_path"
    chmod 644 "${key_path}.pub"

    print_success "Chave SSH gerada em $key_path"
    echo
    print_info "Chave pública para adicionar no servidor remoto:"
    cat "${key_path}.pub"
}

# Copiar chave pública para servidor remoto
copy_ssh_key() {
    local host=$1
    local port=${2:-22}
    local user=${3:-deploy}
    local key_path=${4:-"$HOME/.ssh/whatize_deploy_key"}

    if [ ! -f "${key_path}.pub" ]; then
        print_error "Chave pública não encontrada em ${key_path}.pub"
        return 1
    fi

    print_substep "Copiando chave pública para ${user}@${host}..."

    # Usar ssh-copy-id se disponível
    if command_exists ssh-copy-id; then
        ssh-copy-id -i "$key_path" -p "$port" "${user}@${host}"
    else
        # Fallback manual
        local pub_key=$(cat "${key_path}.pub")
        ssh -p "$port" "${user}@${host}" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$pub_key' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    fi

    if [ $? -eq 0 ]; then
        print_success "Chave copiada com sucesso"
        return 0
    else
        print_error "Falha ao copiar chave"
        return 1
    fi
}

# Testar conexão SSH
test_ssh_connection() {
    local host=$1
    local port=${2:-22}
    local user=${3:-deploy}
    local key_path=$4

    local ssh_cmd="ssh $SSH_OPTS -p $port"
    if [ -n "$key_path" ] && [ -f "$key_path" ]; then
        ssh_cmd="$ssh_cmd -i $key_path"
    fi

    print_substep "Testando conexão SSH com ${user}@${host}:${port}..."

    if $ssh_cmd "${user}@${host}" "echo 'Conexão OK'" &>/dev/null; then
        print_success "Conexão SSH estabelecida"
        return 0
    else
        print_error "Falha na conexão SSH"
        return 1
    fi
}

# Executar comando remoto
ssh_exec() {
    local host=$1
    local port=${2:-22}
    local user=${3:-deploy}
    local key_path=$4
    shift 4
    local command="$@"

    local ssh_cmd="ssh $SSH_OPTS -p $port"
    if [ -n "$key_path" ] && [ -f "$key_path" ]; then
        ssh_cmd="$ssh_cmd -i $key_path"
    fi

    $ssh_cmd "${user}@${host}" "$command"
}

# Executar comando remoto como root
ssh_exec_root() {
    local host=$1
    local port=${2:-22}
    local user=${3:-deploy}
    local key_path=$4
    shift 4
    local command="$@"

    ssh_exec "$host" "$port" "$user" "$key_path" "sudo $command"
}

# Copiar arquivo para servidor remoto
scp_to_remote() {
    local local_path=$1
    local host=$2
    local remote_path=$3
    local port=${4:-22}
    local user=${5:-deploy}
    local key_path=$6

    local scp_cmd="scp $SSH_OPTS -P $port"
    if [ -n "$key_path" ] && [ -f "$key_path" ]; then
        scp_cmd="$scp_cmd -i $key_path"
    fi

    print_substep "Copiando $local_path para ${user}@${host}:${remote_path}..."
    $scp_cmd "$local_path" "${user}@${host}:${remote_path}"

    if [ $? -eq 0 ]; then
        print_success "Arquivo copiado"
        return 0
    else
        print_error "Falha ao copiar arquivo"
        return 1
    fi
}

# Copiar arquivo do servidor remoto
scp_from_remote() {
    local host=$1
    local remote_path=$2
    local local_path=$3
    local port=${4:-22}
    local user=${5:-deploy}
    local key_path=$6

    local scp_cmd="scp $SSH_OPTS -P $port"
    if [ -n "$key_path" ] && [ -f "$key_path" ]; then
        scp_cmd="$scp_cmd -i $key_path"
    fi

    print_substep "Copiando ${user}@${host}:${remote_path} para $local_path..."
    $scp_cmd "${user}@${host}:${remote_path}" "$local_path"

    if [ $? -eq 0 ]; then
        print_success "Arquivo copiado"
        return 0
    else
        print_error "Falha ao copiar arquivo"
        return 1
    fi
}

# Copiar diretório para servidor remoto
rsync_to_remote() {
    local local_path=$1
    local host=$2
    local remote_path=$3
    local port=${4:-22}
    local user=${5:-deploy}
    local key_path=$6

    local rsync_opts="-avz --progress"
    if [ -n "$key_path" ] && [ -f "$key_path" ]; then
        rsync_opts="$rsync_opts -e 'ssh -p $port -i $key_path $SSH_OPTS'"
    else
        rsync_opts="$rsync_opts -e 'ssh -p $port $SSH_OPTS'"
    fi

    print_substep "Sincronizando $local_path com ${user}@${host}:${remote_path}..."
    eval rsync $rsync_opts "$local_path" "${user}@${host}:${remote_path}"

    if [ $? -eq 0 ]; then
        print_success "Sincronização concluída"
        return 0
    else
        print_error "Falha na sincronização"
        return 1
    fi
}

# Verificar se Docker está instalado no remoto
check_remote_docker() {
    local host=$1
    local port=${2:-22}
    local user=${3:-deploy}
    local key_path=$4

    print_substep "Verificando Docker em $host..."

    local docker_version=$(ssh_exec "$host" "$port" "$user" "$key_path" "docker --version 2>/dev/null")

    if [ -n "$docker_version" ]; then
        print_success "Docker instalado: $docker_version"
        return 0
    else
        print_warning "Docker não está instalado em $host"
        return 1
    fi
}

# Instalar Docker em servidor remoto
install_docker_remote() {
    local host=$1
    local port=${2:-22}
    local user=${3:-deploy}
    local key_path=$4

    print_step "Instalando Docker em $host"

    # Script de instalação
    local install_script='
        set -e
        apt-get update -qq
        apt-get install -y -qq apt-transport-https ca-certificates curl gnupg lsb-release
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update -qq
        apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
        systemctl start docker
        systemctl enable docker
        usermod -aG docker '$user'
        echo "Docker instalado com sucesso"
    '

    ssh_exec_root "$host" "$port" "$user" "$key_path" "$install_script"

    if [ $? -eq 0 ]; then
        print_success "Docker instalado em $host"
        return 0
    else
        print_error "Falha ao instalar Docker em $host"
        return 1
    fi
}

# Conectar ao Docker remoto via SSH
get_docker_host_ssh() {
    local host=$1
    local port=${2:-22}
    local user=${3:-deploy}
    local key_path=$4

    if [ -n "$key_path" ] && [ -f "$key_path" ]; then
        echo "ssh://${user}@${host}:${port}?identity_file=${key_path}"
    else
        echo "ssh://${user}@${host}:${port}"
    fi
}

# Executar docker compose em servidor remoto
docker_compose_remote() {
    local host=$1
    local port=${2:-22}
    local user=${3:-deploy}
    local key_path=$4
    local compose_file=$5
    shift 5
    local command="$@"

    local docker_host=$(get_docker_host_ssh "$host" "$port" "$user" "$key_path")

    print_substep "Executando docker compose em $host: $command"
    DOCKER_HOST="$docker_host" docker compose -f "$compose_file" $command
}

# Verificar recursos do servidor remoto
check_remote_resources() {
    local host=$1
    local port=${2:-22}
    local user=${3:-deploy}
    local key_path=$4

    print_step "Verificando recursos de $host"

    local info=$(ssh_exec "$host" "$port" "$user" "$key_path" '
        echo "=== CPU ==="
        nproc
        echo "=== MEMORIA ==="
        free -h | grep Mem
        echo "=== DISCO ==="
        df -h / | tail -1
        echo "=== DOCKER ==="
        docker info 2>/dev/null | grep -E "Containers:|Images:|Server Version:" || echo "Docker não disponível"
    ')

    echo "$info"
}

# Registrar Worker no Lookup Service do Master
register_worker_in_master() {
    local master_host=$1
    local master_lookup_port=${2:-3500}
    local api_key=$3
    local worker_name=$4
    local worker_host=$5
    local worker_ssh_port=${6:-22}
    local worker_ssh_user=${7:-deploy}
    local ssh_key_path=$8

    print_step "Registrando Worker no Master"

    local response=$(curl -s -X POST "http://${master_host}:${master_lookup_port}/vps-servers" \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $api_key" \
        -d "{
            \"name\": \"$worker_name\",
            \"host\": \"$worker_host\",
            \"ssh_port\": $worker_ssh_port,
            \"ssh_user\": \"$worker_ssh_user\",
            \"ssh_key_path\": \"$ssh_key_path\",
            \"is_master\": false,
            \"is_active\": true,
            \"max_instances\": 10
        }")

    if echo "$response" | grep -q '"id"'; then
        print_success "Worker registrado com sucesso"
        echo "$response"
        return 0
    else
        print_error "Falha ao registrar Worker"
        echo "$response"
        return 1
    fi
}
