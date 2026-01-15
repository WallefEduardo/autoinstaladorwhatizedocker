#!/bin/bash
#
# Manifesto - carrega todas as bibliotecas
#

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${LIB_DIR}/colors.sh"
source "${LIB_DIR}/utils.sh"
source "${LIB_DIR}/validation.sh"
source "${LIB_DIR}/docker.sh"
source "${LIB_DIR}/ssh.sh"
source "${LIB_DIR}/menu.sh"
