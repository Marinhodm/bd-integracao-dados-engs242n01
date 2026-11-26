-- Parte 2. SQL compativel com PostgreSQL e MySQL 8.
-- Valor em R$ = quantidade * valor UNITARIO; arredondamento apenas no total.
-- Nao unir vendas por INNER JOIN ao cadastro: isso ocultaria produtos ausentes.
SELECT produto_id, SUM(qtde_vendida) AS quantidade_vendida,
       ROUND(SUM(qtde_vendida * valor_unitario), 2) AS total_vendido_reais
FROM venda
WHERE data_emissao >= '2025-02-01' AND data_emissao < '2025-03-01'
GROUP BY produto_id
ORDER BY produto_id;

-- Agregar entradas antes do JOIN evita multiplicar quantidades quando uma
-- compra chega em varias notas. Item e filial protegem pedidos com varios itens.
CREATE OR REPLACE VIEW vw_recebimentos_por_item AS
SELECT ordem_compra, filial_id, produto_id, item,
       SUM(qtde_recebida) AS quantidade_recebida,
       COUNT(*) AS numero_entradas
FROM entradas_mercadoria
GROUP BY ordem_compra, filial_id, produto_id, item;

CREATE OR REPLACE VIEW vw_conferencia_pedidos AS
SELECT p.*, COALESCE(e.quantidade_recebida, 0) AS recebido_nas_entradas,
       p.qtde_pedida - COALESCE(e.quantidade_recebida, 0) AS saldo_calculado,
       CASE
         WHEN p.ordem_compra <= 0 THEN 'ORDEM_A_CONFIRMAR'
         WHEN COALESCE(e.quantidade_recebida, 0) = 0 THEN 'SEM_RECEBIMENTO'
         WHEN e.quantidade_recebida < p.qtde_pedida THEN 'PARCIAL'
         WHEN e.quantidade_recebida > p.qtde_pedida THEN 'ACIMA_DO_PEDIDO'
         ELSE 'COMPLETO'
       END AS situacao
FROM pedido_compra p
LEFT JOIN vw_recebimentos_por_item e
  ON p.ordem_compra > 0 AND e.ordem_compra = p.ordem_compra
 AND e.filial_id = p.filial_id AND e.produto_id = p.produto_id AND e.item = p.item;

-- Requisicoes sem recebimento comprovado em todo o arquivo.
-- Ordem zero e "a confirmar": ausencia de vinculo nao prova ausencia fisica.
-- Nao substituir ordem_compra por pedido_id: sao campos com papeis distintos.
SELECT pedido_id, ordem_compra, filial_id, produto_id, descricao_produto,
       data_pedido, qtde_pedida, recebido_nas_entradas, situacao
FROM vw_conferencia_pedidos
WHERE situacao IN ('SEM_RECEBIMENTO', 'ORDEM_A_CONFIRMAR')
ORDER BY pedido_id, filial_id, item;

-- Complemento: pedidos parcialmente atendidos, separados dos sem recebimento.
SELECT pedido_id, ordem_compra, filial_id, produto_id,
       qtde_pedida, recebido_nas_entradas, saldo_calculado
FROM vw_conferencia_pedidos
WHERE situacao = 'PARCIAL'
ORDER BY pedido_id;

