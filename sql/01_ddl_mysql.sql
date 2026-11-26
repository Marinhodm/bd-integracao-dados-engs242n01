-- MySQL 8.0.16+ / 8.4. Executar em banco vazio, criado com utf8mb4.
-- DDL no MySQL faz commit implicito: use um banco separado para testes.
CREATE TABLE fornecedor (
    idfornecedor BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    codigo_origem VARCHAR(25) UNIQUE,
    razao_social VARCHAR(255) NOT NULL,
    cadastro_provisorio BOOLEAN NOT NULL DEFAULT FALSE
) ENGINE=InnoDB;

CREATE TABLE produtos_filial (
    filial_id INTEGER NOT NULL,
    produto_id VARCHAR(25) NOT NULL,
    descricao VARCHAR(255) NOT NULL,
    estoque DECIMAL(18,4) NOT NULL DEFAULT 0,
    preco_unitario DECIMAL(18,4) NOT NULL DEFAULT 0,
    preco_compra DECIMAL(18,4) NOT NULL DEFAULT 0,
    preco_venda DECIMAL(18,4) NOT NULL DEFAULT 0,
    idfornecedor BIGINT,
    PRIMARY KEY (filial_id, produto_id),
    FOREIGN KEY (idfornecedor) REFERENCES fornecedor(idfornecedor)
) ENGINE=InnoDB;

CREATE TABLE pedido_compra (
    pedido_id BIGINT NOT NULL,
    data_pedido DATE NOT NULL,
    item INTEGER NOT NULL,
    produto_id VARCHAR(25) NOT NULL,
    descricao_produto VARCHAR(255),
    ordem_compra BIGINT NOT NULL,
    qtde_pedida DECIMAL(18,4) NOT NULL,
    filial_id INTEGER NOT NULL,
    data_entrega DATE,
    qtde_entregue DECIMAL(18,4) NOT NULL DEFAULT 0,
    qtde_pendente DECIMAL(18,4) GENERATED ALWAYS AS (qtde_pedida - qtde_entregue) STORED,
    preco_compra DECIMAL(18,4) NOT NULL,
    fornecedor_id BIGINT,
    PRIMARY KEY (filial_id, pedido_id, produto_id, item),
    FOREIGN KEY (fornecedor_id) REFERENCES fornecedor(idfornecedor),
    INDEX pedido_ordem_idx (ordem_compra, filial_id, produto_id, item)
) ENGINE=InnoDB;

CREATE TABLE entradas_mercadoria (
    data_entrada DATE NOT NULL,
    nro_nfe VARCHAR(255) NOT NULL,
    item INTEGER NOT NULL,
    produto_id VARCHAR(25) NOT NULL,
    descricao_produto VARCHAR(255),
    ordem_compra BIGINT NOT NULL,
    qtde_recebida DECIMAL(18,4) NOT NULL,
    filial_id INTEGER NOT NULL,
    custo_unitario DECIMAL(18,4) NOT NULL,
    PRIMARY KEY (filial_id, ordem_compra, item, produto_id, nro_nfe)
) ENGINE=InnoDB;

CREATE TABLE venda (
    venda_id BIGINT NOT NULL,
    data_emissao DATE NOT NULL,
    horariomov TIME NOT NULL DEFAULT '00:00:00',
    produto_id VARCHAR(25) NOT NULL,
    qtde_vendida DECIMAL(18,4) NOT NULL,
    valor_unitario DECIMAL(18,4) NOT NULL,
    filial_id INTEGER NOT NULL,
    item INTEGER NOT NULL,
    unidade_medida VARCHAR(3),
    PRIMARY KEY (filial_id, venda_id, data_emissao, produto_id, item, horariomov),
    INDEX venda_data_produto_idx (data_emissao, produto_id)
) ENGINE=InnoDB;

-- Movimentos sem produto/pedido valido permanecem para auditoria; veja V03-V06.
CREATE TABLE importacao_lote (
    sha256 CHAR(64) PRIMARY KEY,
    arquivo VARCHAR(255) NOT NULL,
    importado_em TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;
CREATE TABLE importacao_linha (
    sha256 CHAR(64) NOT NULL,
    aba VARCHAR(40) NOT NULL,
    linha INTEGER NOT NULL,
    dados JSON NOT NULL,
    campos_extras JSON,
    PRIMARY KEY (sha256, aba, linha),
    FOREIGN KEY (sha256) REFERENCES importacao_lote(sha256)
) ENGINE=InnoDB;
