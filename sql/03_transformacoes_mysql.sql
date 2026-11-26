-- Parte 3 equivalente para MySQL 8. Usar este arquivo em vez do PostgreSQL.
-- Mais de 10 vezes = >10 pedidos distintos (filial_id, pedido_id) no mes.
WITH requisicoes AS (
    SELECT produto_id, filial_id, pedido_id,
           MAX(descricao_produto) AS descricao_produto,
           MIN(data_pedido) AS data_pedido, SUM(qtde_pedida) AS quantidade
    FROM pedido_compra
    WHERE data_pedido >= '2025-02-01' AND data_pedido < '2025-03-01'
    GROUP BY produto_id, filial_id, pedido_id
)
SELECT CONCAT(produto_id, ' - ', COALESCE(MAX(descricao_produto), 'Sem descricao')) AS produto,
       SUM(quantidade) AS qtde_requisitada, COUNT(*) AS numero_requisicoes,
       DATE_FORMAT(MIN(data_pedido), '%d/%m/%Y') AS primeira_solicitacao,
       DATE_FORMAT(MAX(data_pedido), '%d/%m/%Y') AS ultima_solicitacao
FROM requisicoes
GROUP BY produto_id
HAVING COUNT(*) > 10
ORDER BY produto_id;

SELECT pedido_id,
       CONCAT(produto_id, ' - ', COALESCE(descricao_produto, 'Sem descricao')) AS produto,
       qtde_pedida AS qtde_requisitada,
       DATE_FORMAT(data_pedido, '%d/%m/%Y') AS data_solicitacao
FROM pedido_compra
WHERE data_pedido >= '2025-02-01' AND data_pedido < '2025-03-01'
ORDER BY data_pedido, pedido_id;

SELECT v.venda_id, CONCAT(v.produto_id, ' - ', COALESCE(p.descricao, 'Sem cadastro')) AS produto,
       DATE_FORMAT(v.data_emissao, '%d/%m/%Y') AS data_venda, v.qtde_vendida,
       ROUND(v.qtde_vendida * v.valor_unitario, 2) AS valor_venda
FROM venda v
LEFT JOIN produtos_filial p ON p.filial_id = v.filial_id AND p.produto_id = v.produto_id
WHERE v.data_emissao >= '2025-02-01' AND v.data_emissao < '2025-03-01'
ORDER BY v.data_emissao, v.venda_id;

SELECT filial_id, CONCAT(produto_id, ' - ', descricao) AS produto,
       estoque, preco_venda, idfornecedor
FROM produtos_filial ORDER BY filial_id, produto_id;

-- Cadastro explicitamente provisorio; fornecedor informado e preservado.
-- AUTO_INCREMENT gera a chave com seguranca entre sessoes concorrentes.
DROP TRIGGER IF EXISTS trg_produto_fornecedor;
DELIMITER $$
CREATE TRIGGER trg_produto_fornecedor
BEFORE INSERT ON produtos_filial
FOR EACH ROW
BEGIN
    IF NEW.idfornecedor IS NULL THEN
        INSERT INTO fornecedor (razao_social, cadastro_provisorio)
        VALUES (CONCAT('PENDENTE - fornecedor do produto ', NEW.produto_id), TRUE);
        SET NEW.idfornecedor = LAST_INSERT_ID();
    END IF;
END$$
DELIMITER ;
