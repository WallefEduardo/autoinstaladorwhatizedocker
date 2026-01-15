# AutoInstalador Whatize Docker

Instalador automatizado para o sistema Whatize em containers Docker, com suporte a Multi-VPS.

## Requisitos

### VPS Master (Instalação Completa)
- Ubuntu 20.04+ ou Debian 11+
- Mínimo 4GB RAM (recomendado 8GB)
- Mínimo 20GB disco (recomendado 50GB)
- Acesso root

### VPS Worker (Apenas Instâncias)
- Ubuntu 20.04+ ou Debian 11+
- Mínimo 2GB RAM
- Mínimo 10GB disco
- Acesso root

## Instalação Rápida

### VPS Master

```bash
# Baixar o instalador
cd /root
git clone https://github.com/seu-usuario/AutoInstaladorWhatizeDocker.git
cd AutoInstaladorWhatizeDocker

# Dar permissão de execução
chmod +x *.sh scripts/*.sh

# Executar instalação
./install-master.sh
```

### VPS Worker

```bash
# Na VPS Worker
cd /root
git clone https://github.com/seu-usuario/AutoInstaladorWhatizeDocker.git
cd AutoInstaladorWhatizeDocker
chmod +x *.sh scripts/*.sh
./install-worker.sh

# Na VPS Master, registrar o Worker
./register-worker.sh --host IP_DO_WORKER --name "Worker 1"
```

## Estrutura do Projeto

```
AutoInstaladorWhatizeDocker/
├── install-master.sh         # Instalação Master
├── install-worker.sh         # Instalação Worker
├── register-worker.sh        # Registrar Worker
├── update.sh                 # Atualizar sistema
├── docker/
│   ├── docker-compose.master.yml
│   ├── docker-compose.worker.yml
│   └── .env.example
├── scripts/
│   ├── setup-system.sh
│   ├── build-images.sh
│   ├── backup.sh
│   └── health-check.sh
├── lib/                      # Bibliotecas shell
└── nginx/                    # Templates Nginx
```

## Arquitetura

### VPS Master
```
┌─────────────────────────────────────────────┐
│              VPS MASTER                      │
├─────────────────────────────────────────────┤
│  PostgreSQL (Principal + Lookup)            │
│  Redis (Principal + Baileys)                │
│  Lookup Service (API Gateway)               │
│  Baileys Service (WhatsApp)                 │
│  Backend (Instância Principal)              │
│  Frontend (React + Nginx)                   │
│  Nginx (Reverse Proxy + SSL)                │
└─────────────────────────────────────────────┘
```

### VPS Worker (para instâncias adicionais)
```
┌─────────────────────────────────────────────┐
│              VPS WORKER                      │
├─────────────────────────────────────────────┤
│  Redis (Local)                              │
│  Backend (Instâncias criadas via Master)    │
│  Nginx (Reverse Proxy + SSL)                │
└─────────────────────────────────────────────┘
```

## Comandos Úteis

### Status dos Containers
```bash
cd /root/AutoInstaladorWhatizeDocker/docker
docker compose -f docker-compose.master.yml ps
```

### Ver Logs
```bash
# Todos os containers
docker compose -f docker-compose.master.yml logs -f

# Container específico
docker compose -f docker-compose.master.yml logs -f backend
```

### Reiniciar Serviços
```bash
# Todos
docker compose -f docker-compose.master.yml restart

# Específico
docker compose -f docker-compose.master.yml restart backend
```

### Atualizar Sistema
```bash
cd /root/AutoInstaladorWhatizeDocker
./update.sh
```

### Backup
```bash
./scripts/backup.sh
```

### Health Check
```bash
./scripts/health-check.sh
```

## Configuração

### Variáveis de Ambiente

O arquivo `.env` contém todas as configurações. Principais variáveis:

| Variável | Descrição |
|----------|-----------|
| FRONTEND_URL | URL do frontend (https://app.dominio.com) |
| BACKEND_URL | URL do backend (https://api.dominio.com) |
| LOOKUP_URL | URL do lookup (https://lookup.dominio.com) |
| INSTANCE_CODE | Código da instância (ex: 0001) |
| DB_PASS | Senha do banco de dados |
| REDIS_PASS | Senha do Redis |
| JWT_SECRET | Secret para tokens JWT |
| LOOKUP_API_KEY | Chave de API do Lookup |

### Portas Utilizadas

| Porta | Serviço |
|-------|---------|
| 80/443 | Nginx (HTTP/HTTPS) |
| 3000 | Backend |
| 3001 | Baileys Service |
| 3333 | Frontend |
| 3500 | Lookup Service |
| 5432 | PostgreSQL |
| 5433 | PostgreSQL Lookup |
| 6379 | Redis |
| 6380 | Redis Baileys |

## Multi-VPS

### Adicionar Worker

1. Instale o Worker na VPS remota:
```bash
./install-worker.sh
```

2. No Master, registre o Worker:
```bash
./register-worker.sh \
  --host worker1.dominio.com \
  --name "Worker 1" \
  --ssh-user deploy \
  --ssh-port 22
```

3. Crie instâncias no Worker via painel:
   - Acesse `/super-admin/instances`
   - Clique em "Nova Instância"
   - Selecione o Worker de destino

### Comunicação Master ↔ Worker

- Master se conecta via SSH para gerenciar Docker remoto
- Chaves SSH são geradas automaticamente
- Lookup Service roteia requisições para o backend correto

## Troubleshooting

### Container não inicia
```bash
# Ver logs do container
docker logs whatize_backend

# Ver status detalhado
docker inspect whatize_backend
```

### Erro de conexão com banco
```bash
# Verificar se PostgreSQL está rodando
docker logs whatize_postgres

# Testar conexão
docker exec whatize_postgres psql -U whatize -c "SELECT 1"
```

### SSL não funciona
```bash
# Verificar certificados
certbot certificates

# Renovar manualmente
certbot renew --dry-run
```

### Permissão negada
```bash
# Ajustar permissões dos volumes
docker exec whatize_backend chown -R appuser:appuser /app/public /app/logs
```

## Suporte

- Issues: [GitHub Issues](https://github.com/seu-usuario/AutoInstaladorWhatizeDocker/issues)
- Docs: [Documentação](https://docs.whatize.com)

## Licença

MIT License
