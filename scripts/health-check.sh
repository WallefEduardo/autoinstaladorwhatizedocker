#!/bin/bash
#
# Health Check - Verifica saúde dos serviços
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/manifest.sh"

print_banner

print_step "Health Check do Sistema"

# Carregar configurações
if [ -f "${SCRIPT_DIR}/../docker/.env" ]; then
    source "${SCRIPT_DIR}/../docker/.env"
fi

COMPOSE_FILE="${SCRIPT_DIR}/../docker/docker-compose.master.yml"

# ===========================================
# STATUS DOS CONTAINERS
# ===========================================
print_step "Status dos Containers"

if [ -f "$COMPOSE_FILE" ]; then
    docker compose -f "$COMPOSE_FILE" ps
else
    docker ps --filter "label=whatize=true" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
fi

# ===========================================
# HEALTH CHECK DOS SERVIÇOS
# ===========================================
print_step "Health Check dos Serviços"

check_endpoint() {
    local name=$1
    local url=$2
    local expected=${3:-200}

    local status=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")

    if [ "$status" = "$expected" ] || [ "$status" = "200" ] || [ "$status" = "301" ] || [ "$status" = "302" ]; then
        print_success "$name: OK (HTTP $status)"
        return 0
    else
        print_error "$name: FALHOU (HTTP $status)"
        return 1
    fi
}

errors=0

# Lookup Service
check_endpoint "Lookup Service" "http://localhost:3500/health" || ((errors++))

# Baileys Service
check_endpoint "Baileys Service" "http://localhost:3001/health" || ((errors++))

# Backend (sem auth)
check_endpoint "Backend" "http://localhost:3000/health" || true  # Pode dar 401 sem token

# Frontend
check_endpoint "Frontend" "http://localhost:3333/" || ((errors++))

# ===========================================
# RECURSOS DO SISTEMA
# ===========================================
print_step "Recursos do Sistema"

# Memória
print_substep "Memória:"
free -h | grep -E "Mem|Swap"

# Disco
print_substep "Disco:"
df -h / | tail -1

# CPU
print_substep "CPU Load:"
uptime | awk -F'load average:' '{print $2}'

# ===========================================
# MÉTRICAS DOS CONTAINERS
# ===========================================
print_step "Métricas dos Containers"

docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" \
    $(docker ps -q --filter "label=whatize=true") 2>/dev/null || true

# ===========================================
# VERIFICAR LOGS DE ERRO RECENTES
# ===========================================
print_step "Erros Recentes nos Logs"

for container in whatize_backend whatize_lookup whatize_baileys; do
    if docker ps -q -f "name=$container" &>/dev/null; then
        error_count=$(docker logs --since 5m "$container" 2>&1 | grep -i "error\|fatal\|exception" | wc -l)
        if [ "$error_count" -gt 0 ]; then
            print_warning "$container: $error_count erros nos últimos 5 minutos"
        else
            print_success "$container: Sem erros recentes"
        fi
    fi
done

# ===========================================
# RESUMO
# ===========================================
print_step "Resumo"

if [ $errors -eq 0 ]; then
    echo -e "${GREEN}✓ Todos os serviços estão saudáveis!${NC}"
    exit 0
else
    echo -e "${RED}✗ $errors serviço(s) com problemas${NC}"
    echo
    echo -e "${YELLOW}Verifique os logs para mais detalhes:${NC}"
    echo -e "  docker compose -f ${COMPOSE_FILE} logs -f"
    exit 1
fi
