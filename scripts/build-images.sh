#!/bin/bash
#
# Build das imagens Docker
#

set -e

# Carregar bibliotecas
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/manifest.sh"

# Carregar configurações
if [ -f "${SCRIPT_DIR}/../docker/.env" ]; then
    source "${SCRIPT_DIR}/../docker/.env"
fi

print_step "Build das Imagens Docker"

WHATIZE_PATH="${WHATIZE_PATH:-/home/deploy/whatize}"
VERSION="${VERSION:-latest}"
NO_CACHE="${1:-false}"

# Verificar se o código existe
if [ ! -d "$WHATIZE_PATH" ]; then
    print_error "Diretório do código não encontrado: $WHATIZE_PATH"
    exit 1
fi

cd "$WHATIZE_PATH"

# Opções de build
BUILD_OPTS=""
if [ "$NO_CACHE" = "--no-cache" ] || [ "$NO_CACHE" = "true" ]; then
    BUILD_OPTS="--no-cache"
    print_info "Build sem cache habilitado"
fi

# ===========================================
# BUILD LOOKUP SERVICE
# ===========================================
print_substep "Building: whatize-lookup:${VERSION}"

if [ -d "lookup-service" ] && [ -f "lookup-service/Dockerfile" ]; then
    docker build $BUILD_OPTS \
        -t "whatize-lookup:${VERSION}" \
        -t "whatize-lookup:latest" \
        -f lookup-service/Dockerfile \
        lookup-service/

    print_success "whatize-lookup:${VERSION} built"
else
    print_warning "lookup-service/Dockerfile não encontrado, pulando..."
fi

# ===========================================
# BUILD BAILEYS SERVICE
# ===========================================
print_substep "Building: whatize-baileys:${VERSION}"

if [ -d "BaileysService" ] && [ -f "BaileysService/Dockerfile" ]; then
    docker build $BUILD_OPTS \
        -t "whatize-baileys:${VERSION}" \
        -t "whatize-baileys:latest" \
        -f BaileysService/Dockerfile \
        BaileysService/

    print_success "whatize-baileys:${VERSION} built"
else
    print_warning "BaileysService/Dockerfile não encontrado, pulando..."
fi

# ===========================================
# BUILD BACKEND
# ===========================================
print_substep "Building: whatize-backend:${VERSION}"

if [ -d "backend" ]; then
    # Preferir Dockerfile.optimized se existir
    if [ -f "backend/Dockerfile.optimized" ]; then
        DOCKERFILE="backend/Dockerfile.optimized"
    elif [ -f "backend/Dockerfile" ]; then
        DOCKERFILE="backend/Dockerfile"
    else
        print_error "Nenhum Dockerfile encontrado para backend"
        exit 1
    fi

    docker build $BUILD_OPTS \
        -t "whatize-backend:${VERSION}" \
        -t "whatize-backend:latest" \
        -f "$DOCKERFILE" \
        backend/

    print_success "whatize-backend:${VERSION} built"
else
    print_error "Diretório backend/ não encontrado"
    exit 1
fi

# ===========================================
# BUILD FRONTEND
# ===========================================
print_substep "Building: whatize-frontend:${VERSION}"

if [ -d "frontend" ]; then
    # Preferir Dockerfile.optimized se existir
    if [ -f "frontend/Dockerfile.optimized" ]; then
        DOCKERFILE="frontend/Dockerfile.optimized"
    elif [ -f "frontend/Dockerfile" ]; then
        DOCKERFILE="frontend/Dockerfile"
    else
        print_error "Nenhum Dockerfile encontrado para frontend"
        exit 1
    fi

    # Build args para o frontend
    docker build $BUILD_OPTS \
        --build-arg REACT_APP_BACKEND_URL="${BACKEND_URL:-http://localhost:3000}" \
        --build-arg REACT_APP_LOOKUP_URL="${LOOKUP_URL:-http://localhost:3500}" \
        --build-arg REACT_APP_HOURS_CLOSE_TICKETS_AUTO=24 \
        -t "whatize-frontend:${VERSION}" \
        -t "whatize-frontend:latest" \
        -f "$DOCKERFILE" \
        frontend/

    print_success "whatize-frontend:${VERSION} built"
else
    print_error "Diretório frontend/ não encontrado"
    exit 1
fi

# ===========================================
# RESUMO
# ===========================================
print_step "Resumo das Imagens"

echo -e "${WHITE}Imagens construídas:${NC}"
docker images --filter "reference=whatize-*" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}"

print_success "Build concluído com sucesso!"
