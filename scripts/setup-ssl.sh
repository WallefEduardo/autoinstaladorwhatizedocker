#!/bin/bash
#
# Setup SSL - Configura certificados SSL com Certbot
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/manifest.sh"

# Carregar configurações
if [ -f "${SCRIPT_DIR}/../docker/.env" ]; then
    source "${SCRIPT_DIR}/../docker/.env"
fi

print_step "Configurando SSL com Certbot"

# ===========================================
# EXTRAIR DOMÍNIOS DAS URLs
# ===========================================
extract_domain() {
    local url=$1
    echo "$url" | sed -E 's|https?://||' | sed -E 's|/.*||'
}

FRONTEND_DOMAIN=$(extract_domain "${FRONTEND_URL}")
BACKEND_DOMAIN=$(extract_domain "${BACKEND_URL}")
LOOKUP_DOMAIN=$(extract_domain "${LOOKUP_URL}")

print_info "Domínios a configurar:"
echo "  Frontend: $FRONTEND_DOMAIN"
echo "  Backend:  $BACKEND_DOMAIN"
echo "  Lookup:   $LOOKUP_DOMAIN"
echo

# ===========================================
# CRIAR DIRETÓRIO PARA DESAFIO ACME
# ===========================================
mkdir -p /var/www/certbot

# ===========================================
# CONFIGURAR NGINX TEMPORÁRIO (HTTP)
# ===========================================
print_step "Configurando Nginx para validação"

# Backup configurações existentes
mkdir -p /etc/nginx/sites-available.bak
cp /etc/nginx/sites-available/* /etc/nginx/sites-available.bak/ 2>/dev/null || true

# Criar configuração temporária para cada domínio
for domain in "$FRONTEND_DOMAIN" "$BACKEND_DOMAIN" "$LOOKUP_DOMAIN"; do
    cat > "/etc/nginx/sites-available/${domain}" << EOF
server {
    listen 80;
    server_name ${domain};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 200 'OK';
        add_header Content-Type text/plain;
    }
}
EOF
    ln -sf "/etc/nginx/sites-available/${domain}" "/etc/nginx/sites-enabled/${domain}"
done

# Testar e recarregar nginx
nginx -t && systemctl reload nginx

# ===========================================
# GERAR CERTIFICADOS
# ===========================================
print_step "Gerando certificados SSL"

# Todos os domínios únicos
DOMAINS_UNIQUE=$(echo "$FRONTEND_DOMAIN $BACKEND_DOMAIN $LOOKUP_DOMAIN" | tr ' ' '\n' | sort -u | tr '\n' ' ')

for domain in $DOMAINS_UNIQUE; do
    print_substep "Gerando certificado para: $domain"

    if [ -d "/etc/letsencrypt/live/${domain}" ]; then
        print_info "Certificado já existe para $domain"
        continue
    fi

    certbot certonly \
        --webroot \
        --webroot-path=/var/www/certbot \
        --email "${SSL_EMAIL}" \
        --agree-tos \
        --no-eff-email \
        --non-interactive \
        -d "$domain"

    if [ $? -eq 0 ]; then
        print_success "Certificado gerado para $domain"
    else
        print_error "Falha ao gerar certificado para $domain"
    fi
done

# ===========================================
# APLICAR TEMPLATES NGINX COM SSL
# ===========================================
print_step "Aplicando configuração Nginx com SSL"

TEMPLATES_DIR="${SCRIPT_DIR}/../nginx/templates"

# Frontend
if [ -f "${TEMPLATES_DIR}/frontend.conf.template" ]; then
    envsubst '${FRONTEND_DOMAIN} ${FRONTEND_URL}' < "${TEMPLATES_DIR}/frontend.conf.template" > "/etc/nginx/sites-available/${FRONTEND_DOMAIN}"
fi

# Backend
if [ -f "${TEMPLATES_DIR}/backend.conf.template" ]; then
    export WHATIZE_PATH="${WHATIZE_PATH:-/home/deploy/whatize}"
    envsubst '${BACKEND_DOMAIN} ${FRONTEND_URL} ${WHATIZE_PATH}' < "${TEMPLATES_DIR}/backend.conf.template" > "/etc/nginx/sites-available/${BACKEND_DOMAIN}"
fi

# Lookup
if [ -f "${TEMPLATES_DIR}/lookup.conf.template" ]; then
    envsubst '${LOOKUP_DOMAIN}' < "${TEMPLATES_DIR}/lookup.conf.template" > "/etc/nginx/sites-available/${LOOKUP_DOMAIN}"
fi

# ===========================================
# COPIAR ARQUIVOS DE CONFIGURAÇÃO GLOBAL
# ===========================================
cp "${SCRIPT_DIR}/../nginx/ssl-params.conf" /etc/nginx/ssl-params.conf 2>/dev/null || true

# ===========================================
# TESTAR E RECARREGAR NGINX
# ===========================================
print_step "Finalizando configuração"

if nginx -t; then
    systemctl reload nginx
    print_success "Nginx configurado com SSL"
else
    print_error "Erro na configuração do Nginx"
    exit 1
fi

# ===========================================
# CONFIGURAR RENOVAÇÃO AUTOMÁTICA
# ===========================================
print_step "Configurando renovação automática"

# Criar job de renovação
CRON_JOB="0 3 * * * certbot renew --quiet --post-hook 'systemctl reload nginx'"

if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    print_success "Renovação automática configurada (3h da manhã)"
else
    print_info "Renovação automática já está configurada"
fi

# ===========================================
# EXIBIR RESUMO
# ===========================================
print_step "SSL Configurado!"

echo
echo -e "${GREEN}Certificados instalados:${NC}"
for domain in $DOMAINS_UNIQUE; do
    if [ -d "/etc/letsencrypt/live/${domain}" ]; then
        EXPIRY=$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/${domain}/cert.pem" 2>/dev/null | cut -d= -f2)
        echo -e "  ${WHITE}${domain}${NC}: Expira em ${CYAN}${EXPIRY}${NC}"
    fi
done
echo

print_success "Configuração SSL concluída!"
