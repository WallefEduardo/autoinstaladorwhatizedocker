-- ===========================================
-- Migration: Adicionar suporte Multi-VPS
-- ===========================================

-- Tabela de servidores VPS
CREATE TABLE IF NOT EXISTS vps_servers (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    host VARCHAR(255) NOT NULL,
    ssh_port INTEGER DEFAULT 22,
    ssh_user VARCHAR(50) DEFAULT 'deploy',
    ssh_key_path VARCHAR(255),
    docker_port INTEGER DEFAULT 2375,
    is_master BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    max_instances INTEGER DEFAULT 10,
    current_instances INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Índices
CREATE INDEX IF NOT EXISTS idx_vps_servers_host ON vps_servers(host);
CREATE INDEX IF NOT EXISTS idx_vps_servers_is_active ON vps_servers(is_active);
CREATE INDEX IF NOT EXISTS idx_vps_servers_is_master ON vps_servers(is_master);

-- Adicionar campos na tabela company_instances
ALTER TABLE company_instances
ADD COLUMN IF NOT EXISTS vps_server_id INTEGER REFERENCES vps_servers(id);

ALTER TABLE company_instances
ADD COLUMN IF NOT EXISTS container_id VARCHAR(100);

ALTER TABLE company_instances
ADD COLUMN IF NOT EXISTS internal_port INTEGER DEFAULT 3000;

-- Criar índice para vps_server_id
CREATE INDEX IF NOT EXISTS idx_company_instances_vps_server
ON company_instances(vps_server_id);

-- Inserir VPS Master (localhost) como primeiro servidor
INSERT INTO vps_servers (name, host, is_master, is_active, max_instances)
VALUES ('Master', 'localhost', true, true, 100)
ON CONFLICT DO NOTHING;

-- Atualizar instâncias existentes para apontar para o Master
UPDATE company_instances
SET vps_server_id = (SELECT id FROM vps_servers WHERE is_master = true LIMIT 1)
WHERE vps_server_id IS NULL;
