#!/bin/bash
#
# Setup do Sistema - Instala Docker e dependências
#

set -e

# Carregar bibliotecas
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/manifest.sh"

print_step "Configurando Sistema"

# Verificar se é root
check_root

# Verificar sistema operacional
check_os

# ===========================================
# ATUALIZAR SISTEMA
# ===========================================
print_substep "Atualizando sistema..."
apt-get update -qq
apt-get upgrade -y -qq

# ===========================================
# INSTALAR DEPENDÊNCIAS BÁSICAS
# ===========================================
print_substep "Instalando dependências básicas..."
apt-get install -y -qq \
    curl \
    wget \
    git \
    nano \
    htop \
    unzip \
    zip \
    net-tools \
    dnsutils \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    netcat-openbsd

print_success "Dependências básicas instaladas"

# ===========================================
# INSTALAR DOCKER
# ===========================================
install_docker

# ===========================================
# INSTALAR NGINX
# ===========================================
print_substep "Instalando Nginx..."
apt-get install -y -qq nginx

systemctl start nginx
systemctl enable nginx

print_success "Nginx instalado"

# ===========================================
# INSTALAR CERTBOT
# ===========================================
print_substep "Instalando Certbot..."

# Instalar via snap (recomendado)
if command_exists snap; then
    snap install core 2>/dev/null || true
    snap refresh core 2>/dev/null || true
    snap install --classic certbot 2>/dev/null || apt-get install -y -qq certbot python3-certbot-nginx
else
    apt-get install -y -qq certbot python3-certbot-nginx
fi

# Criar link simbólico se necessário
if [ ! -f /usr/bin/certbot ] && [ -f /snap/bin/certbot ]; then
    ln -sf /snap/bin/certbot /usr/bin/certbot
fi

print_success "Certbot instalado"

# ===========================================
# CRIAR USUÁRIO DEPLOY
# ===========================================
if [ -n "$DEPLOY_USER" ] && [ -n "$DEPLOY_PASS" ]; then
    create_user_if_not_exists "$DEPLOY_USER" "$DEPLOY_PASS"

    # Adicionar ao grupo docker
    usermod -aG docker "$DEPLOY_USER" 2>/dev/null || true

    # Criar diretório home se não existir
    mkdir -p "/home/$DEPLOY_USER"
    chown "$DEPLOY_USER:$DEPLOY_USER" "/home/$DEPLOY_USER"
fi

# ===========================================
# CONFIGURAR FIREWALL (UFW)
# ===========================================
if command_exists ufw; then
    print_substep "Configurando firewall..."

    ufw default deny incoming 2>/dev/null || true
    ufw default allow outgoing 2>/dev/null || true
    ufw allow ssh 2>/dev/null || true
    ufw allow http 2>/dev/null || true
    ufw allow https 2>/dev/null || true
    ufw allow 3000/tcp 2>/dev/null || true  # Backend
    ufw allow 3001/tcp 2>/dev/null || true  # Baileys
    ufw allow 3500/tcp 2>/dev/null || true  # Lookup

    # Não habilitar automaticamente para não bloquear acesso
    print_info "Firewall configurado (não habilitado automaticamente)"
    print_info "Para habilitar: ufw enable"
fi

# ===========================================
# AJUSTES DE PERFORMANCE
# ===========================================
print_substep "Aplicando ajustes de performance..."

# Aumentar limites de arquivos abertos
cat > /etc/security/limits.d/whatize.conf << 'EOF'
* soft nofile 65535
* hard nofile 65535
* soft nproc 65535
* hard nproc 65535
EOF

# Ajustes de sysctl para melhor performance de rede
cat > /etc/sysctl.d/99-whatize.conf << 'EOF'
# Increase system file descriptor limit
fs.file-max = 65535

# Increase TCP max buffer size
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216

# Increase Linux auto-tuning TCP buffer limits
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# Enable TCP window scaling
net.ipv4.tcp_window_scaling = 1

# Increase the maximum amount of memory buffers
net.core.optmem_max = 65535

# Increase the number of incoming connections
net.core.somaxconn = 65535

# Increase the number of outstanding SYN requests
net.ipv4.tcp_max_syn_backlog = 65535

# Reduce TIME_WAIT
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_tw_reuse = 1
EOF

sysctl -p /etc/sysctl.d/99-whatize.conf 2>/dev/null || true

print_success "Ajustes de performance aplicados"

# ===========================================
# CONFIGURAR TIMEZONE
# ===========================================
print_substep "Configurando timezone..."
timedatectl set-timezone America/Sao_Paulo 2>/dev/null || true

print_success "Sistema configurado com sucesso!"
