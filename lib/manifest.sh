#!/bin/bash
#
# Manifesto - carrega todas as bibliotecas
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/colors.sh"
source "${SCRIPT_DIR}/utils.sh"
source "${SCRIPT_DIR}/validation.sh"
source "${SCRIPT_DIR}/docker.sh"
source "${SCRIPT_DIR}/ssh.sh"
source "${SCRIPT_DIR}/menu.sh"
