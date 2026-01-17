#!/bin/bash
#
# Instalador Master - Instala VPS Master completa com todos os serviços
#

set -e

# Obter diretório do script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Carregar bibliotecas
source "${SCRIPT_DIR}/lib/manifest.sh"

# ===========================================
# VERIFICAÇÕES INICIAIS
# ===========================================
print_banner

# Verificar se é root
if [ "$(id -u)" != "0" ]; then
    print_error "Este script deve ser executado como root"
    echo "Execute: sudo $0"
    exit 1
fi

# Verificar requisitos do sistema
validate_system_requirements

# ===========================================
# COLETAR INFORMAÇÕES
# ===========================================
while true; do
    if collect_master_info; then
        break
    fi
done

# ===========================================
# GERAR SECRETS AUTOMÁTICOS
# ===========================================
print_step "Gerando secrets"

JWT_SECRET=$(generate_secret)
JWT_REFRESH_SECRET=$(generate_secret)
LOOKUP_API_KEY=$(generate_secret)
BAILEYS_API_KEY=$(generate_secret)
BAILEYS_WEBHOOK_TOKEN=$(generate_secret)
ENV_TOKEN="wtV"

print_success "Secrets gerados"

# ===========================================
# CONFIGURAR SISTEMA
# ===========================================
export DEPLOY_USER="${DEPLOY_USER:-deploy}"
export DEPLOY_PASS="${DEPLOY_PASS}"

"${SCRIPT_DIR}/scripts/setup-system.sh"

# ===========================================
# CLONAR REPOSITÓRIO
# ===========================================
print_step "Clonando repositório"

WHATIZE_PATH="/home/${DEPLOY_USER}/whatize"

if [ -d "$WHATIZE_PATH" ]; then
    print_info "Diretório já existe, atualizando..."
    git config --global --add safe.directory "$WHATIZE_PATH"
    cd "$WHATIZE_PATH"
    git fetch --all
    git reset --hard origin/${GIT_BRANCH}
else
    print_substep "Clonando de $GIT_REPO_URL..."

    # Se tem token, usar no URL
    if [ -n "$GIT_TOKEN" ]; then
        GIT_URL=$(echo "$GIT_REPO_URL" | sed "s|https://|https://${GIT_TOKEN}@|")
    else
        GIT_URL="$GIT_REPO_URL"
    fi

    git clone -b "$GIT_BRANCH" "$GIT_URL" "$WHATIZE_PATH"
fi

chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "$WHATIZE_PATH"
print_success "Repositório clonado em $WHATIZE_PATH"

# ===========================================
# CRIAR ARQUIVO .ENV
# ===========================================
print_step "Criando arquivo de configuração"

ENV_FILE="${SCRIPT_DIR}/docker/.env"

cat > "$ENV_FILE" << EOF
# ===========================================
# WHATIZE - Docker Environment Configuration
# Gerado em: $(date)
# ===========================================

# Versão
VERSION=latest

# Path do código
WHATIZE_PATH=${WHATIZE_PATH}

# Domínios
FRONTEND_URL=https://${FRONTEND_DOMAIN}
BACKEND_URL=https://${BACKEND_DOMAIN}
LOOKUP_URL=https://${LOOKUP_DOMAIN}

# Instância
INSTANCE_CODE=${INSTANCE_CODE}
INSTANCE_NAME=${INSTANCE_NAME}

# Banco de dados principal
DB_NAME=whatize
DB_USER=whatize
DB_PASS=${DB_PASS}
DB_PORT=5432

# Banco de dados Lookup
LOOKUP_DB_PASS=${LOOKUP_DB_PASS:-$(generate_password 24)}

# Redis
REDIS_PASS=${REDIS_PASS}
REDIS_PORT=6379
REDIS_BAILEYS_PORT=6380

# JWT
JWT_SECRET=${JWT_SECRET}
JWT_REFRESH_SECRET=${JWT_REFRESH_SECRET}

# Lookup Service
LOOKUP_API_KEY=${LOOKUP_API_KEY}
LOOKUP_PORT=3500
LOOKUP_DB_PORT=5433

# Baileys Service
BAILEYS_API_KEY=${BAILEYS_API_KEY}
BAILEYS_WEBHOOK_TOKEN=${BAILEYS_WEBHOOK_TOKEN}
BAILEYS_PORT=3001

# Backend
BACKEND_PORT=3000
ENV_TOKEN=${ENV_TOKEN}

# Frontend
FRONTEND_PORT=3333

# SSL
SSL_EMAIL=${SSL_EMAIL}

# Deploy
DEPLOY_USER=${DEPLOY_USER}
EOF

chmod 600 "$ENV_FILE"
print_success "Arquivo .env criado"

# ===========================================
# BUILD DAS IMAGENS
# ===========================================
export WHATIZE_PATH
export BACKEND_URL="https://${BACKEND_DOMAIN}"
export LOOKUP_URL="https://${LOOKUP_DOMAIN}"
export VERSION="latest"

"${SCRIPT_DIR}/scripts/build-images.sh"

# ===========================================
# CRIAR REDE DOCKER
# ===========================================
print_step "Configurando Docker"

docker_create_network "whatize_net" "172.28.0.0/16"

# ===========================================
# SUBIR CONTAINERS
# ===========================================
print_step "Iniciando containers"

cd "${SCRIPT_DIR}/docker"

# Subir apenas infraestrutura primeiro (postgres, redis)
print_substep "Iniciando banco de dados e cache..."
docker compose -f docker-compose.master.yml up -d postgres postgres-lookup redis redis-baileys
sleep 15

# Aguardar postgres ficar pronto
print_substep "Aguardando banco de dados..."
until docker exec whatize_postgres pg_isready -U whatize -d whatize > /dev/null 2>&1; do
    sleep 2
done
print_success "Banco de dados pronto"

# Rodar migrations usando container temporário
print_substep "Executando migrations do banco de dados..."
docker run --rm --network whatize_net \
    -e DB_HOST=postgres \
    -e DB_PORT=5432 \
    -e DB_USER=whatize \
    -e DB_PASS=${DB_PASS} \
    -e DB_NAME=whatize \
    whatize-backend:latest npm run db:migrate 2>&1 || {
    print_warning "Migrations falharam, tentando novamente..."
    sleep 5
    docker run --rm --network whatize_net \
        -e DB_HOST=postgres \
        -e DB_PORT=5432 \
        -e DB_USER=whatize \
        -e DB_PASS=${DB_PASS} \
        -e DB_NAME=whatize \
        whatize-backend:latest npm run db:migrate 2>&1 || print_error "Falha nas migrations"
}
print_success "Migrations executadas"

# Rodar seeders para popular dados iniciais
print_substep "Populando banco de dados com dados iniciais..."
docker run --rm --network whatize_net \
    -e DB_HOST=postgres \
    -e DB_PORT=5432 \
    -e DB_USER=whatize \
    -e DB_PASS=${DB_PASS} \
    -e DB_NAME=whatize \
    whatize-backend:latest npm run db:seed 2>&1 || {
    print_warning "Seeds falharam, tentando novamente..."
    sleep 5
    docker run --rm --network whatize_net \
        -e DB_HOST=postgres \
        -e DB_PORT=5432 \
        -e DB_USER=whatize \
        -e DB_PASS=${DB_PASS} \
        -e DB_NAME=whatize \
        whatize-backend:latest npm run db:seed 2>&1 || print_warning "Seeds falharam - pode precisar rodar manualmente"
}
print_success "Dados iniciais populados"

# Agora subir todos os serviços
print_substep "Iniciando todos os serviços..."
docker compose -f docker-compose.master.yml up -d

print_substep "Aguardando containers ficarem saudáveis..."
sleep 30

# Verificar saúde
docker_health_check docker-compose.master.yml || true

# ===========================================
# CONFIGURAR NGINX
# ===========================================
print_step "Configurando Nginx"

# Frontend
cat > /etc/nginx/sites-available/whatize-frontend << EOF
server {
    listen 80;
    server_name ${FRONTEND_DOMAIN};

    location / {
        proxy_pass http://localhost:3333;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

# Backend
cat > /etc/nginx/sites-available/whatize-backend << EOF
server {
    listen 80;
    server_name ${BACKEND_DOMAIN};

    client_max_body_size 50M;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }

    location /socket.io {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Lookup
cat > /etc/nginx/sites-available/whatize-lookup << EOF
server {
    listen 80;
    server_name ${LOOKUP_DOMAIN};

    client_max_body_size 50M;

    location / {
        proxy_pass http://localhost:3500;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }

    location /api/socket.io {
        proxy_pass http://localhost:3500;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Habilitar sites
ln -sf /etc/nginx/sites-available/whatize-frontend /etc/nginx/sites-enabled/
ln -sf /etc/nginx/sites-available/whatize-backend /etc/nginx/sites-enabled/
ln -sf /etc/nginx/sites-available/whatize-lookup /etc/nginx/sites-enabled/

# Remover default se existir
rm -f /etc/nginx/sites-enabled/default

# Testar e recarregar
nginx -t
systemctl reload nginx

print_success "Nginx configurado"

# ===========================================
# CONFIGURAR SSL
# ===========================================
print_step "Configurando SSL"

print_substep "Obtendo certificados SSL para os domínios..."

certbot --nginx \
    --non-interactive \
    --agree-tos \
    --email "${SSL_EMAIL}" \
    --domains "${FRONTEND_DOMAIN},${BACKEND_DOMAIN},${LOOKUP_DOMAIN}" \
    --redirect || {
    print_warning "Falha ao obter certificados automaticamente"
    print_info "Execute manualmente após configurar o DNS:"
    print_info "certbot --nginx -d ${FRONTEND_DOMAIN} -d ${BACKEND_DOMAIN} -d ${LOOKUP_DOMAIN}"
}

# Configurar renovação automática
systemctl enable certbot.timer 2>/dev/null || true
systemctl start certbot.timer 2>/dev/null || true

print_success "SSL configurado"

# ===========================================
# EXECUTAR MIGRATIONS DO LOOKUP
# ===========================================
print_step "Configurando banco de dados do Lookup"

print_substep "Executando migrations do Lookup Service..."
docker exec whatize_lookup npm run db:migrate 2>&1 || {
    print_warning "Migrations do Lookup falharam, tentando novamente..."
    sleep 5
    docker exec whatize_lookup npm run db:migrate 2>&1 || print_warning "Falha nas migrations do Lookup"
}
print_success "Migrations do Lookup executadas"

# ===========================================
# REGISTRAR INSTÂNCIA NO LOOKUP
# ===========================================
print_step "Registrando instância principal"

sleep 5  # Aguardar serviços estabilizarem

# Registrar via API
curl -s -X POST "http://localhost:3500/companies" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: ${LOOKUP_API_KEY}" \
    -d "{
        \"code\": \"${INSTANCE_CODE}\",
        \"backendUrl\": \"https://${BACKEND_DOMAIN}\",
        \"companyName\": \"${INSTANCE_NAME}\"
    }" || print_warning "Instância pode já estar registrada"

# Definir como padrão para signup
curl -s -X PUT "http://localhost:3500/signup-config/${INSTANCE_CODE}" \
    -H "X-API-Key: ${LOOKUP_API_KEY}" || true

print_success "Instância registrada no Lookup"

# ===========================================
# FINALIZAÇÃO
# ===========================================
print_step "Instalação Concluída!"

echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    INSTALAÇÃO COMPLETA!                       ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${WHITE}URLs de Acesso:${NC}"
echo -e "  Frontend: ${CYAN}https://${FRONTEND_DOMAIN}${NC}"
echo -e "  Backend:  ${CYAN}https://${BACKEND_DOMAIN}${NC}"
echo -e "  Lookup:   ${CYAN}https://${LOOKUP_DOMAIN}${NC}"
echo
echo -e "${WHITE}Credenciais Padrão:${NC}"
echo -e "  Email: ${CYAN}admin@whatize.com${NC}"
echo -e "  Senha: ${CYAN}admin123${NC}"
echo
echo -e "${WHITE}Código da Instância:${NC} ${CYAN}${INSTANCE_CODE}${NC}"
echo
echo -e "${WHITE}Comandos Úteis:${NC}"
echo -e "  Status:   ${CYAN}docker compose -f ${SCRIPT_DIR}/docker/docker-compose.master.yml ps${NC}"
echo -e "  Logs:     ${CYAN}docker compose -f ${SCRIPT_DIR}/docker/docker-compose.master.yml logs -f${NC}"
echo -e "  Restart:  ${CYAN}docker compose -f ${SCRIPT_DIR}/docker/docker-compose.master.yml restart${NC}"
echo
echo -e "${YELLOW}⚠ IMPORTANTE: Altere a senha do admin após o primeiro login!${NC}"
echo
