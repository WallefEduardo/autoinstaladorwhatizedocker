#!/bin/bash
#
# Funções Docker
#

# Instalar Docker
install_docker() {
    print_step "Instalando Docker"

    if command_exists docker; then
        print_info "Docker já está instalado"
        docker --version
        return 0
    fi

    print_substep "Instalando dependências..."
    apt-get update -qq
    apt-get install -y -qq \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    print_substep "Adicionando repositório Docker..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    print_substep "Instalando Docker Engine..."
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin

    # Iniciar e habilitar Docker
    systemctl start docker
    systemctl enable docker

    print_success "Docker instalado com sucesso"
    docker --version
}

# Verificar status dos containers
docker_status() {
    local compose_file=$1

    if [ -n "$compose_file" ] && [ -f "$compose_file" ]; then
        docker compose -f "$compose_file" ps
    else
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    fi
}

# Parar todos os containers do projeto
docker_stop_all() {
    local compose_file=$1

    if [ -n "$compose_file" ] && [ -f "$compose_file" ]; then
        docker compose -f "$compose_file" down
    else
        print_warning "Arquivo compose não especificado"
    fi
}

# Reiniciar containers
docker_restart() {
    local compose_file=$1
    local service=$2

    if [ -n "$compose_file" ] && [ -f "$compose_file" ]; then
        if [ -n "$service" ]; then
            docker compose -f "$compose_file" restart "$service"
        else
            docker compose -f "$compose_file" restart
        fi
    fi
}

# Construir imagens
docker_build() {
    local compose_file=$1
    local service=$2
    local no_cache=${3:-false}

    local build_opts=""
    if [ "$no_cache" = "true" ]; then
        build_opts="--no-cache"
    fi

    if [ -n "$compose_file" ] && [ -f "$compose_file" ]; then
        if [ -n "$service" ]; then
            docker compose -f "$compose_file" build $build_opts "$service"
        else
            docker compose -f "$compose_file" build $build_opts
        fi
    fi
}

# Subir containers
docker_up() {
    local compose_file=$1
    local detached=${2:-true}

    local up_opts=""
    if [ "$detached" = "true" ]; then
        up_opts="-d"
    fi

    if [ -n "$compose_file" ] && [ -f "$compose_file" ]; then
        docker compose -f "$compose_file" up $up_opts
    fi
}

# Ver logs
docker_logs() {
    local compose_file=$1
    local service=$2
    local lines=${3:-100}
    local follow=${4:-false}

    local log_opts="--tail $lines"
    if [ "$follow" = "true" ]; then
        log_opts="$log_opts -f"
    fi

    if [ -n "$compose_file" ] && [ -f "$compose_file" ]; then
        if [ -n "$service" ]; then
            docker compose -f "$compose_file" logs $log_opts "$service"
        else
            docker compose -f "$compose_file" logs $log_opts
        fi
    fi
}

# Executar comando em container
docker_exec() {
    local container=$1
    shift
    local command="$@"

    docker exec -it "$container" $command
}

# Verificar saúde dos containers
docker_health_check() {
    local compose_file=$1

    print_step "Verificando saúde dos containers"

    local containers
    if [ -n "$compose_file" ] && [ -f "$compose_file" ]; then
        containers=$(docker compose -f "$compose_file" ps -q)
    else
        containers=$(docker ps -q --filter "label=whatize=true")
    fi

    local all_healthy=true
    for container in $containers; do
        local name=$(docker inspect --format '{{.Name}}' "$container" | sed 's/\///')
        local status=$(docker inspect --format '{{.State.Status}}' "$container")
        local health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "$container")

        if [ "$status" = "running" ]; then
            if [ "$health" = "healthy" ] || [ "$health" = "no-healthcheck" ]; then
                print_success "$name: $status ($health)"
            else
                print_warning "$name: $status ($health)"
                all_healthy=false
            fi
        else
            print_error "$name: $status"
            all_healthy=false
        fi
    done

    if [ "$all_healthy" = "true" ]; then
        return 0
    else
        return 1
    fi
}

# Limpar recursos Docker não utilizados
docker_cleanup() {
    print_step "Limpando recursos Docker não utilizados"

    print_substep "Removendo containers parados..."
    docker container prune -f

    print_substep "Removendo imagens não utilizadas..."
    docker image prune -f

    print_substep "Removendo volumes não utilizados..."
    docker volume prune -f

    print_substep "Removendo networks não utilizadas..."
    docker network prune -f

    print_success "Limpeza concluída"
}

# Criar rede Docker se não existir
docker_create_network() {
    local network_name=$1
    local subnet=${2:-"172.28.0.0/16"}

    if docker network inspect "$network_name" &>/dev/null; then
        print_info "Rede $network_name já existe"
        return 0
    fi

    print_substep "Criando rede Docker $network_name..."
    docker network create \
        --driver bridge \
        --subnet "$subnet" \
        "$network_name"

    print_success "Rede $network_name criada"
}

# Obter IP do container
docker_get_container_ip() {
    local container=$1
    local network=${2:-"whatize_net"}

    docker inspect -f "{{.NetworkSettings.Networks.${network}.IPAddress}}" "$container" 2>/dev/null
}

# Verificar se imagem existe localmente
docker_image_exists() {
    local image=$1
    docker image inspect "$image" &>/dev/null
}

# Pull de imagem
docker_pull_image() {
    local image=$1
    print_substep "Baixando imagem $image..."
    docker pull "$image"
}

# Tag de imagem
docker_tag_image() {
    local source=$1
    local target=$2
    docker tag "$source" "$target"
}

# Push de imagem para registry
docker_push_image() {
    local image=$1
    print_substep "Enviando imagem $image..."
    docker push "$image"
}

# Exportar imagem para arquivo
docker_export_image() {
    local image=$1
    local output=$2
    print_substep "Exportando imagem $image para $output..."
    docker save -o "$output" "$image"
}

# Importar imagem de arquivo
docker_import_image() {
    local input=$1
    print_substep "Importando imagem de $input..."
    docker load -i "$input"
}
