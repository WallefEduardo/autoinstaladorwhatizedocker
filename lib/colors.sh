#!/bin/bash
#
# Cores e estilos para terminal
#

# Reset
NC='\033[0m'

# Cores regulares
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'

# Cores em negrito
BOLD_BLACK='\033[1;30m'
BOLD_RED='\033[1;31m'
BOLD_GREEN='\033[1;32m'
BOLD_YELLOW='\033[1;33m'
BOLD_BLUE='\033[1;34m'
BOLD_PURPLE='\033[1;35m'
BOLD_CYAN='\033[1;36m'
BOLD_WHITE='\033[1;37m'

# Cores de fundo
BG_BLACK='\033[40m'
BG_RED='\033[41m'
BG_GREEN='\033[42m'
BG_YELLOW='\033[43m'
BG_BLUE='\033[44m'
BG_PURPLE='\033[45m'
BG_CYAN='\033[46m'
BG_WHITE='\033[47m'

# Estilos
BOLD='\033[1m'
DIM='\033[2m'
UNDERLINE='\033[4m'
BLINK='\033[5m'
REVERSE='\033[7m'

# Funções de output
print_banner() {
    clear
    echo -e "${BOLD_CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    echo "║   █████╗ ██╗   ██╗████████╗ ██████╗                         ║"
    echo "║  ██╔══██╗██║   ██║╚══██╔══╝██╔═══██╗                        ║"
    echo "║  ███████║██║   ██║   ██║   ██║   ██║                        ║"
    echo "║  ██╔══██║██║   ██║   ██║   ██║   ██║                        ║"
    echo "║  ██║  ██║╚██████╔╝   ██║   ╚██████╔╝                        ║"
    echo "║  ╚═╝  ╚═╝ ╚═════╝    ╚═╝    ╚═════╝                         ║"
    echo "║                                                              ║"
    echo "║   ██╗███╗   ██╗███████╗████████╗ █████╗ ██╗     ███████╗   ║"
    echo "║   ██║████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██║     ██╔════╝   ║"
    echo "║   ██║██╔██╗ ██║███████╗   ██║   ███████║██║     █████╗     ║"
    echo "║   ██║██║╚██╗██║╚════██║   ██║   ██╔══██║██║     ██╔══╝     ║"
    echo "║   ██║██║ ╚████║███████║   ██║   ██║  ██║███████╗███████╗   ║"
    echo "║   ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚══════╝   ║"
    echo "║                                                              ║"
    echo "║            WHATIZE - Docker Auto Installer                   ║"
    echo "║                     v1.0.0                                   ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_step() {
    echo -e "\n${BOLD_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD_WHITE}  $1${NC}"
    echo -e "${BOLD_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_substep() {
    echo -e "${CYAN}→${NC} $1"
}

spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}
