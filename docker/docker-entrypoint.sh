#!/bin/bash
set -e

echo "=========================================="
echo "  WHATIZE - Docker Entrypoint"
echo "=========================================="
echo "Instance Code: ${INSTANCE_CODE:-N/A}"
echo "Instance Name: ${INSTANCE_NAME:-N/A}"
echo "Port: ${PORT:-3000}"
echo "Environment: ${NODE_ENV:-development}"
echo "=========================================="

# ===========================================
# Aguardar banco de dados
# ===========================================
echo "[DB] Aguardando banco de dados..."

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
MAX_ATTEMPTS=30
ATTEMPT=1

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    if nc -z "$DB_HOST" "$DB_PORT" 2>/dev/null; then
        echo "[DB] Banco de dados disponível!"
        break
    fi
    echo "[DB] Tentativa $ATTEMPT/$MAX_ATTEMPTS - Aguardando..."
    sleep 2
    ATTEMPT=$((ATTEMPT + 1))
done

if [ $ATTEMPT -gt $MAX_ATTEMPTS ]; then
    echo "[DB] ERRO: Timeout aguardando banco de dados"
    exit 1
fi

# ===========================================
# Aguardar Redis (opcional)
# ===========================================
if [ -n "$REDIS_URI" ]; then
    echo "[REDIS] Aguardando Redis..."

    # Extrair host e porta do REDIS_URI
    REDIS_HOST=$(echo "$REDIS_URI" | sed -n 's/.*@\([^:]*\).*/\1/p')
    REDIS_PORT_NUM=$(echo "$REDIS_URI" | sed -n 's/.*:\([0-9]*\)\/.*/\1/p')
    REDIS_HOST=${REDIS_HOST:-localhost}
    REDIS_PORT_NUM=${REDIS_PORT_NUM:-6379}

    MAX_ATTEMPTS=15
    ATTEMPT=1

    while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
        if nc -z "$REDIS_HOST" "$REDIS_PORT_NUM" 2>/dev/null; then
            echo "[REDIS] Redis disponível!"
            break
        fi
        echo "[REDIS] Tentativa $ATTEMPT/$MAX_ATTEMPTS - Aguardando..."
        sleep 2
        ATTEMPT=$((ATTEMPT + 1))
    done

    if [ $ATTEMPT -gt $MAX_ATTEMPTS ]; then
        echo "[REDIS] AVISO: Redis não disponível, continuando mesmo assim..."
    fi
fi

# ===========================================
# Executar Migrations
# ===========================================
echo "[MIGRATIONS] Executando migrations do banco de dados..."

cd /app

if npx sequelize-cli db:migrate 2>&1; then
    echo "[MIGRATIONS] Migrations executadas com sucesso!"
else
    echo "[MIGRATIONS] Aviso: Algumas migrations podem já estar aplicadas"
fi

# ===========================================
# Executar Seeds
# ===========================================
echo "[SEEDS] Executando seeds do banco de dados..."

if npx sequelize-cli db:seed:all 2>&1; then
    echo "[SEEDS] Seeds executados com sucesso!"
else
    echo "[SEEDS] Aviso: Alguns seeds podem já estar aplicados"
fi

# ===========================================
# Criar diretórios necessários
# ===========================================
echo "[DIRS] Verificando diretórios..."

mkdir -p /app/public/company1
mkdir -p /app/logs

# Ajustar permissões se rodando como root
if [ "$(id -u)" = "0" ]; then
    chown -R appuser:appuser /app/public /app/logs 2>/dev/null || true
fi

echo "[DIRS] Diretórios verificados!"

# ===========================================
# Iniciar aplicação
# ===========================================
echo "=========================================="
echo "  Iniciando aplicação na porta ${PORT:-3000}"
echo "=========================================="

exec node dist/server.js
