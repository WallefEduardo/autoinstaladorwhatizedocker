#!/bin/bash
#
# Funções de menu interativo
#

# Ler input com valor padrão
read_input() {
    local prompt=$1
    local default=$2
    local var_name=$3
    local validation_func=$4

    while true; do
        if [ -n "$default" ]; then
            read -p "$prompt [$default]: " input
            input=${input:-$default}
        else
            read -p "$prompt: " input
        fi

        # Se não tem função de validação, aceitar qualquer input
        if [ -z "$validation_func" ]; then
            eval "$var_name='$input'"
            return 0
        fi

        # Validar input
        if $validation_func "$input"; then
            eval "$var_name='$input'"
            return 0
        else
            print_error "Valor inválido. Tente novamente."
        fi
    done
}

# Ler senha (oculta)
read_password() {
    local prompt=$1
    local var_name=$2
    local confirm=${3:-false}

    while true; do
        read -sp "$prompt: " password
        echo

        if [ "$confirm" = "true" ]; then
            read -sp "Confirme a senha: " password_confirm
            echo

            if [ "$password" != "$password_confirm" ]; then
                print_error "Senhas não conferem. Tente novamente."
                continue
            fi
        fi

        if [ -n "$password" ]; then
            eval "$var_name='$password'"
            return 0
        else
            print_error "Senha não pode ser vazia"
        fi
    done
}

# Menu de seleção
select_option() {
    local prompt=$1
    shift
    local options=("$@")

    echo -e "\n${BOLD_WHITE}$prompt${NC}"
    echo

    local i=1
    for option in "${options[@]}"; do
        echo -e "  ${CYAN}$i)${NC} $option"
        ((i++))
    done

    echo
    while true; do
        read -p "Escolha uma opção [1-${#options[@]}]: " choice

        if [[ $choice =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#options[@]} ]; then
            return $((choice - 1))
        else
            print_error "Opção inválida"
        fi
    done
}

# Menu de confirmação Sim/Não
confirm_menu() {
    local prompt=$1
    local default=${2:-n}

    echo
    if [ "$default" = "y" ]; then
        read -p "$prompt [Y/n]: " response
        response=${response:-y}
    else
        read -p "$prompt [y/N]: " response
        response=${response:-n}
    fi

    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

# Coletar informações da instalação Master
collect_master_info() {
    print_step "Configuração da Instalação"

    # Domínios
    echo -e "${BOLD_WHITE}Configure os domínios:${NC}\n"

    read_input "Domínio do Frontend (ex: app.seudominio.com)" "" FRONTEND_DOMAIN validate_domain
    read_input "Domínio do Backend (ex: api.seudominio.com)" "" BACKEND_DOMAIN validate_domain
    read_input "Domínio do Lookup (ex: lookup.seudominio.com)" "" LOOKUP_DOMAIN validate_domain

    # Código da instância
    echo -e "\n${BOLD_WHITE}Configure a instância principal:${NC}\n"

    read_input "Código da instância (3-10 caracteres, ex: 0001)" "0001" INSTANCE_CODE validate_instance_code
    INSTANCE_CODE=$(echo "$INSTANCE_CODE" | tr '[:lower:]' '[:upper:]')

    read_input "Nome da instância" "Principal" INSTANCE_NAME

    # Senhas
    echo -e "\n${BOLD_WHITE}Configure as senhas (deixe em branco para gerar automaticamente):${NC}\n"

    read -sp "Senha do banco de dados [auto]: " DB_PASS
    echo
    DB_PASS=${DB_PASS:-$(generate_password 24)}

    read -sp "Senha do Redis [auto]: " REDIS_PASS
    echo
    REDIS_PASS=${REDIS_PASS:-$(generate_password 24)}

    read -sp "Senha do usuário deploy [auto]: " DEPLOY_PASS
    echo
    DEPLOY_PASS=${DEPLOY_PASS:-$(generate_password 16)}

    # Repositório
    echo -e "\n${BOLD_WHITE}Configure o repositório:${NC}\n"

    read_input "URL do repositório Git" "https://github.com/seu-usuario/whatize.git" GIT_REPO_URL
    read_input "Branch do repositório" "main" GIT_BRANCH

    read -sp "Token do Git (para repos privados, deixe vazio se público): " GIT_TOKEN
    echo

    # Email para SSL
    echo -e "\n${BOLD_WHITE}Configure o SSL:${NC}\n"

    read_input "Email para certificado SSL" "" SSL_EMAIL validate_email

    # Resumo
    print_step "Resumo da Configuração"

    echo -e "${WHITE}Frontend:${NC} https://${FRONTEND_DOMAIN}"
    echo -e "${WHITE}Backend:${NC} https://${BACKEND_DOMAIN}"
    echo -e "${WHITE}Lookup:${NC} https://${LOOKUP_DOMAIN}"
    echo -e "${WHITE}Instância:${NC} ${INSTANCE_CODE} - ${INSTANCE_NAME}"
    echo -e "${WHITE}Repositório:${NC} ${GIT_REPO_URL} (${GIT_BRANCH})"
    echo -e "${WHITE}SSL Email:${NC} ${SSL_EMAIL}"

    echo
    if ! confirm_menu "As informações estão corretas?"; then
        return 1
    fi

    return 0
}

# Coletar informações da instalação Worker
collect_worker_info() {
    print_step "Configuração do Worker"

    echo -e "${BOLD_WHITE}Configure a conexão com o Master:${NC}\n"

    read_input "Host/IP do Master" "" MASTER_HOST
    read_input "Porta do Lookup no Master" "3500" MASTER_LOOKUP_PORT validate_port
    read_input "API Key do Lookup" "" LOOKUP_API_KEY

    # Nome do Worker
    echo -e "\n${BOLD_WHITE}Configure este Worker:${NC}\n"

    read_input "Nome deste Worker" "Worker-$(hostname)" WORKER_NAME
    read_input "Domínio base para backends (ex: worker1.seudominio.com)" "" WORKER_DOMAIN validate_domain

    # Senhas
    echo -e "\n${BOLD_WHITE}Configure as senhas (deixe em branco para gerar automaticamente):${NC}\n"

    read -sp "Senha do Redis local [auto]: " REDIS_PASS
    echo
    REDIS_PASS=${REDIS_PASS:-$(generate_password 24)}

    read -sp "Senha do usuário deploy [auto]: " DEPLOY_PASS
    echo
    DEPLOY_PASS=${DEPLOY_PASS:-$(generate_password 16)}

    # Email para SSL
    echo -e "\n${BOLD_WHITE}Configure o SSL:${NC}\n"

    read_input "Email para certificado SSL" "" SSL_EMAIL validate_email

    # Resumo
    print_step "Resumo da Configuração"

    echo -e "${WHITE}Master:${NC} ${MASTER_HOST}:${MASTER_LOOKUP_PORT}"
    echo -e "${WHITE}Worker:${NC} ${WORKER_NAME}"
    echo -e "${WHITE}Domínio:${NC} ${WORKER_DOMAIN}"
    echo -e "${WHITE}SSL Email:${NC} ${SSL_EMAIL}"

    echo
    if ! confirm_menu "As informações estão corretas?"; then
        return 1
    fi

    return 0
}

# Menu principal
show_main_menu() {
    print_banner

    echo -e "${BOLD_WHITE}Selecione o tipo de instalação:${NC}\n"
    echo -e "  ${CYAN}1)${NC} Instalar VPS Master (instalação completa)"
    echo -e "  ${CYAN}2)${NC} Instalar VPS Worker (apenas para instâncias adicionais)"
    echo -e "  ${CYAN}3)${NC} Atualizar sistema existente"
    echo -e "  ${CYAN}4)${NC} Verificar status"
    echo -e "  ${CYAN}5)${NC} Backup dos dados"
    echo -e "  ${CYAN}6)${NC} Desinstalar"
    echo -e "  ${CYAN}0)${NC} Sair"

    echo
    read -p "Escolha uma opção: " choice

    case $choice in
        1) return 1 ;;  # Install Master
        2) return 2 ;;  # Install Worker
        3) return 3 ;;  # Update
        4) return 4 ;;  # Status
        5) return 5 ;;  # Backup
        6) return 6 ;;  # Uninstall
        0) return 0 ;;  # Exit
        *) return 99 ;; # Invalid
    esac
}
