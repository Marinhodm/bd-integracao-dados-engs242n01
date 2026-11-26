-- Parte 3: PostgreSQL. Equivalente MySQL em 03_transformacoes_mysql.sql.
-- "Mais de 10 vezes" = mais de 10 pedidos DISTINTOS por produto em fevereiro.
-- A identidade do pedido e (filial_id, pedido_id). Repetir o produto em varios
-- itens do mesmo pedido nao cria outra requisicao. A base tem no maximo dois;
-- portanto o resultado vazio e esperado, nao um motivo para alterar os dados.
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
       TO_CHAR(MIN(data_pedido), 'DD/MM/YYYY') AS primeira_solicitacao,
       TO_CHAR(MAX(data_pedido), 'DD/MM/YYYY') AS ultima_solicitacao
FROM requisicoes
GROUP BY produto_id
HAVING COUNT(*) > 10
ORDER BY produto_id;

-- Exibicao individual de pedidos, sem misturar quantidade de unidades com vezes.
SELECT pedido_id,
       CONCAT(produto_id, ' - ', COALESCE(descricao_produto, 'Sem descricao')) AS produto,
       qtde_pedida AS qtde_requisitada,
       TO_CHAR(data_pedido, 'DD/MM/YYYY') AS data_solicitacao
FROM pedido_compra
WHERE data_pedido >= '2025-02-01' AND data_pedido < '2025-03-01'
ORDER BY data_pedido, pedido_id;

-- Vendas: LEFT JOIN mantem as vendas cujo cadastro do produto esta ausente.
SELECT v.venda_id, CONCAT(v.produto_id, ' - ', COALESCE(p.descricao, 'Sem cadastro')) AS produto,
       TO_CHAR(v.data_emissao, 'DD/MM/YYYY') AS data_venda, v.qtde_vendida,
       ROUND(v.qtde_vendida * v.valor_unitario, 2) AS valor_venda
FROM venda v
LEFT JOIN produtos_filial p ON p.filial_id = v.filial_id AND p.produto_id = v.produto_id
WHERE v.data_emissao >= '2025-02-01' AND v.data_emissao < '2025-03-01'
ORDER BY v.data_emissao, v.venda_id;

SELECT filial_id, CONCAT(produto_id, ' - ', descricao) AS produto,
       estoque, preco_venda, idfornecedor
FROM produtos_filial ORDER BY filial_id, produto_id;

-- Interpretacao da trigger: ao cadastrar produto sem idfornecedor, cria um
-- fornecedor PROVISORIO e atribui sua chave numerica ao produto. Nao inventa
-- uma razao social real. Se o ID foi informado, preserva-o e a FK o valida.
-- IDENTITY evita colisao entre sessoes; MAX(id)+1 nao e usado.
CREATE OR REPLACE FUNCTION gerar_fornecedor_produto()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.idfornecedor IS NULL THEN
        INSERT INTO fornecedor (razao_social, cadastro_provisorio)
        VALUES ('PENDENTE - fornecedor do produto ' || NEW.produto_id, TRUE)
        RETURNING idfornecedor INTO NEW.idfornecedor;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_produto_fornecedor ON produtos_filial;
CREATE TRIGGER trg_produto_fornecedor
BEFORE INSERT ON produtos_filial
FOR EACH ROW EXECUTE FUNCTION gerar_fornecedor_produto();

