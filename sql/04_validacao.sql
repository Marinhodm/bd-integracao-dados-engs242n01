-- Parte 4: PostgreSQL e MySQL 8. Executar apos 02_consultas.sql.
-- V01: reconciliacao da origem (linhas de dados, sem cabecalho) com o banco.
SELECT 'fornecedor' AS tabela, 20 AS esperado, COUNT(*) AS importado FROM fornecedor
UNION ALL SELECT 'produtos_filial', 20, COUNT(*) FROM produtos_filial
UNION ALL SELECT 'pedido_compra', 29, COUNT(*) FROM pedido_compra
UNION ALL SELECT 'entradas_mercadoria', 20, COUNT(*) FROM entradas_mercadoria
UNION ALL SELECT 'venda', 33, COUNT(*) FROM venda;

-- V02: fechamento de fevereiro. Valor bruto com precisao; arredondar ao final.
SELECT COUNT(*) AS linhas, SUM(qtde_vendida) AS quantidade,
       SUM(qtde_vendida * valor_unitario) AS valor_sem_arredondamento,
       ROUND(SUM(qtde_vendida * valor_unitario), 2) AS valor_reais
FROM venda
WHERE data_emissao >= '2025-02-01' AND data_emissao < '2025-03-01';

-- V03: vendas sem cadastro para a combinacao produto/filial (13 no arquivo).
SELECT v.* FROM venda v
LEFT JOIN produtos_filial p ON p.filial_id = v.filial_id AND p.produto_id = v.produto_id
WHERE p.produto_id IS NULL
ORDER BY v.venda_id;

-- V04: ordem ausente/invalida; nao preencher automaticamente com pedido_id.
SELECT * FROM pedido_compra WHERE ordem_compra <= 0 ORDER BY pedido_id;

-- V05: entrega prevista/informada anterior a solicitacao; confirmar semantica.
SELECT pedido_id, produto_id, data_pedido, data_entrega
FROM pedido_compra WHERE data_entrega < data_pedido ORDER BY pedido_id;

-- V06: entrada sem correspondencia pela chave de vinculo completa.
SELECT e.* FROM entradas_mercadoria e
WHERE NOT EXISTS (
    SELECT 1 FROM pedido_compra p
    WHERE p.ordem_compra > 0 AND p.ordem_compra = e.ordem_compra
      AND p.filial_id = e.filial_id AND p.produto_id = e.produto_id AND p.item = e.item
) ORDER BY e.nro_nfe;

-- V07: entrada anterior a solicitacao do pedido relacionado.
SELECT p.pedido_id, e.nro_nfe, p.data_pedido, e.data_entrada
FROM pedido_compra p JOIN entradas_mercadoria e
  ON p.ordem_compra > 0 AND p.ordem_compra = e.ordem_compra
 AND p.filial_id = e.filial_id AND p.produto_id = e.produto_id AND p.item = e.item
WHERE e.data_entrada < p.data_pedido ORDER BY p.pedido_id;

-- V08: qtde_entregue declarada difere das notas (apenas vinculos confirmados).
SELECT p.pedido_id, p.produto_id, p.qtde_entregue, e.quantidade_recebida
FROM pedido_compra p JOIN vw_recebimentos_por_item e
  ON p.ordem_compra > 0 AND p.ordem_compra = e.ordem_compra
 AND p.filial_id = e.filial_id AND p.produto_id = e.produto_id AND p.item = e.item
WHERE p.qtde_entregue <> e.quantidade_recebida ORDER BY p.pedido_id;

-- V09: recebimento maior que pedido; nao limitar silenciosamente ao pedido.
SELECT pedido_id, produto_id, qtde_pedida, recebido_nas_entradas, saldo_calculado
FROM vw_conferencia_pedidos WHERE situacao = 'ACIMA_DO_PEDIDO' ORDER BY pedido_id;

-- V10: quantidades fracionarias com unidade UN; alerta a validar com o cliente.
SELECT venda_id, produto_id, qtde_vendida, unidade_medida
FROM venda WHERE unidade_medida = 'UN' AND qtde_vendida <> FLOOR(qtde_vendida)
ORDER BY venda_id;

-- V11: celulas extras sem cabecalho preservadas, nunca importadas por posicao.
SELECT aba, linha, campos_extras FROM importacao_linha
WHERE campos_extras IS NOT NULL ORDER BY aba, linha;

-- V12: verificacao de duplicidades pelas chaves naturais (zero nesta origem).
SELECT 'venda' AS tabela, CONCAT(filial_id, '/', venda_id, '/', produto_id, '/', item,
       '/', data_emissao, '/', horariomov) AS chave, COUNT(*) AS ocorrencias
FROM venda GROUP BY filial_id, venda_id, produto_id, item, data_emissao, horariomov HAVING COUNT(*) > 1
UNION ALL
SELECT 'pedido_compra', CONCAT(filial_id, '/', pedido_id, '/', produto_id, '/', item), COUNT(*)
FROM pedido_compra GROUP BY filial_id, pedido_id, produto_id, item HAVING COUNT(*) > 1
UNION ALL
SELECT 'entradas_mercadoria', CONCAT(filial_id, '/', ordem_compra, '/', item, '/', produto_id, '/', nro_nfe), COUNT(*)
FROM entradas_mercadoria GROUP BY filial_id, ordem_compra, item, produto_id, nro_nfe HAVING COUNT(*) > 1
UNION ALL
SELECT 'produtos_filial', CONCAT(filial_id, '/', produto_id), COUNT(*)
FROM produtos_filial GROUP BY filial_id, produto_id HAVING COUNT(*) > 1
UNION ALL
SELECT 'fornecedor', codigo_origem, COUNT(*) FROM fornecedor
WHERE codigo_origem IS NOT NULL GROUP BY codigo_origem HAVING COUNT(*) > 1;

-- V13: valores negativos/quantidades inconsistentes (zero na base fornecida).
SELECT 'venda' AS tabela, CONCAT(venda_id, '/', item) AS registro
FROM venda WHERE qtde_vendida < 0 OR valor_unitario < 0
UNION ALL
SELECT 'pedido_compra', CONCAT(pedido_id, '/', item) FROM pedido_compra
WHERE qtde_pedida < 0 OR qtde_entregue < 0 OR preco_compra < 0 OR qtde_pendente < 0
UNION ALL
SELECT 'entradas_mercadoria', nro_nfe FROM entradas_mercadoria
WHERE qtde_recebida < 0 OR custo_unitario < 0
UNION ALL
SELECT 'produtos_filial', produto_id FROM produtos_filial
WHERE estoque < 0 OR preco_unitario < 0 OR preco_compra < 0 OR preco_venda < 0;

-- V14: chave de vinculo ambigua (zero na base); se houver, validar antes de somar.
SELECT ordem_compra, filial_id, produto_id, item, COUNT(*) AS pedidos
FROM pedido_compra WHERE ordem_compra > 0
GROUP BY ordem_compra, filial_id, produto_id, item HAVING COUNT(*) > 1;

-- V15: mapeamento numerico dos fornecedores e codigos originais preservados.
SELECT p.pedido_id, p.fornecedor_id AS id_interno, f.codigo_origem, f.razao_social
FROM pedido_compra p LEFT JOIN fornecedor f ON f.idfornecedor = p.fornecedor_id
ORDER BY p.pedido_id;

-- V16: fornecedores provisorios gerados pela trigger, pendentes de cadastro.
SELECT * FROM fornecedor WHERE cadastro_provisorio = TRUE ORDER BY idfornecedor;

-- V17: preco de venda menor que custo no cadastro: alerta comercial, nao
-- necessariamente erro (pode haver promocao, perda ou preco desatualizado).
SELECT filial_id, produto_id, preco_compra, preco_venda
FROM produtos_filial WHERE preco_venda < preco_compra ORDER BY produto_id;

-- V18: custo recebido diferente do preco pedido; verificar nota e negociacao.
SELECT p.pedido_id, e.nro_nfe, p.preco_compra, e.custo_unitario
FROM pedido_compra p JOIN entradas_mercadoria e
  ON p.ordem_compra > 0 AND p.ordem_compra = e.ordem_compra
 AND p.filial_id = e.filial_id AND p.produto_id = e.produto_id AND p.item = e.item
WHERE p.preco_compra <> e.custo_unitario ORDER BY p.pedido_id;

-- V19: rastreabilidade: quantidade de linhas guardadas por aba e lote.
SELECT sha256, aba, COUNT(*) AS linhas FROM importacao_linha GROUP BY sha256, aba ORDER BY aba;

-- V20: pendencias na posicao de 28/02/2025, inclusive pedidos de janeiro.
-- Entradas de marco nao quitam o saldo de fevereiro. Quantidades com ordem
-- zero continuam "a confirmar". Datas incoerentes sao exibidas em V05/V07.
WITH recebido_ate_fevereiro AS (
    SELECT ordem_compra, filial_id, produto_id, item, SUM(qtde_recebida) AS recebido
    FROM entradas_mercadoria WHERE data_entrada < '2025-03-01'
    GROUP BY ordem_compra, filial_id, produto_id, item
)
SELECT p.pedido_id, p.produto_id, p.data_pedido, p.qtde_pedida,
       COALESCE(e.recebido, 0) AS recebido_ate_fevereiro,
       p.qtde_pedida - COALESCE(e.recebido, 0) AS saldo_em_fevereiro,
       CASE WHEN p.ordem_compra <= 0 THEN 'ORDEM_A_CONFIRMAR' ELSE 'VINCULO_EXISTENTE' END AS confianca_vinculo
FROM pedido_compra p LEFT JOIN recebido_ate_fevereiro e
  ON p.ordem_compra > 0 AND p.ordem_compra = e.ordem_compra
 AND p.filial_id = e.filial_id AND p.produto_id = e.produto_id AND p.item = e.item
WHERE p.data_pedido < '2025-03-01'
  AND (p.ordem_compra <= 0 OR p.qtde_pedida > COALESCE(e.recebido, 0))
ORDER BY p.pedido_id;

-- V21: conciliacao por filial em fevereiro (nao excluir produtos sem cadastro).
SELECT filial_id, COUNT(*) AS linhas, SUM(qtde_vendida) AS quantidade,
       ROUND(SUM(qtde_vendida * valor_unitario), 2) AS valor_reais
FROM venda WHERE data_emissao >= '2025-02-01' AND data_emissao < '2025-03-01'
GROUP BY filial_id ORDER BY filial_id;

