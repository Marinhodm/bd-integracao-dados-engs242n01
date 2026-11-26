# Parte 4 — validação com o cliente (fevereiro de 2025)

## Objetivo e posição dos dados

Validar a fidelidade da importação, o fechamento de fevereiro e as regras de
negócio antes da homologação. Os SQLs foram executados em PostgreSQL e MySQL;
as divergências abaixo são da origem preservada, não registros descartados.
Todas as consultas estão em [sql/04_validacao.sql](../sql/04_validacao.sql),
identificadas de V01 a V21. Elas dependem das views criadas em `02_consultas.sql`.

O período de vendas é **01/02/2025 inclusive até 01/03/2025 exclusive**.
Para a posição de pedidos em 28/02, também entram pedidos anteriores ao mês;
recebimentos de março não abatem o saldo de fevereiro (V20).

## Roteiro da reunião — 30 minutos

| Tempo | Ponto a apresentar | Consulta/evidência | Decisão esperada |
| --- | --- | --- | --- |
| 0–5 min | Origem, hash, cinco abas, contagens e rastreabilidade | V01/V19 e relatórios de importação | Confirmar arquivo e abrangência |
| 5–12 min | Vendas por produto e filial em fevereiro | Parte 2, V02/V21 | Confirmar quantidade e valor unitário; política de arredondamento |
| 12–20 min | Pedidos pendentes, parciais e entradas não vinculadas | V04/V06/V08/V09/V20 | Identificar ordens corretas e qual fonte comprova o recebimento |
| 20–26 min | Cadastros, datas, unidades e preços suspeitos | V03/V05/V07/V10/V11/V15/V17/V18 | Definir correções respaldadas por documentos |
| 26–30 min | Responsáveis, prazos e aceite | Lista de pendências abaixo | Registrar aceite parcial ou reprovação e plano de saneamento |

Pontos que precisam de resposta do cliente:

1. `valor_unitario` é o preço por unidade? O cálculo adotado é quantidade ×
   valor_unitario; não somamos apenas os preços. Confirmar descontos, devoluções
   e se valores são brutos, pois o arquivo não traz campos para esses ajustes.
2. As vendas com unidade UN podem ter quantidade fracionária? Não arredondar
   automaticamente os cinco casos: isso alteraria as vendas.
3. `data_entrega` é previsão ou entrega efetiva? Mesmo que seja previsão, validar
   por que há datas anteriores à solicitação; confrontar pedido e nota fiscal.
4. Qual é a ordem real dos pedidos 19–29? Eles trazem zero, e as entradas NFE19 e
   NFE20 trazem ordens 19 e 20. A semelhança entre pedido_id e ordem_compra não
   autoriza substituir uma coluna pela outra.
5. Qual cadastro correto deve atender P21–P28 e suas filiais? Não há descrição,
   custo ou fornecedor suficientes para inventar esse cadastro.
6. Os códigos numéricos de fornecedor dos pedidos correspondem a F1...F20?
   O mapeamento adotado é explícito e reversível, com os valores originais guardados.
7. As células sem cabeçalho em M:W são restos de edição ou registros válidos?
   Elas foram preservadas, mas não usadas para sobrescrever as colunas nomeadas.
8. Confirmar a interpretação de “mais de 10 vezes”: dez pedidos distintos,
   não dez unidades. Na base, nenhum produto tem mais de dois pedidos no período.
9. Confirmar o uso do cadastro provisório na trigger: produto novo sem fornecedor
   recebe uma chave numérica relacionada a um fornecedor sinalizado como pendente.

## Técnicas de conferência

- **Reconciliação quantitativa:** comparar as cinco contagens e as 122 linhas de
  rastreabilidade; cabeçalhos e linhas totalmente vazias não são registros.
- **Reconciliação de conteúdo:** a importação compara todos os campos tratados
  com os valores efetivamente lidos do banco, não apenas COUNT(*).
- **Reconciliação financeira:** comparar produto, filial e total; manter quatro
  casas na carga e arredondar a soma final a dois decimais. Somar valores já
  arredondados pode produzir diferença de centavos em outros conjuntos.
- **Conferência documental:** revisar todos os casos excepcionais com notas,
  pedidos e cadastro mestre; a base é pequena o suficiente para revisão completa.
- **Integridade:** chaves primárias, FKs de fornecedores, detecção de vínculos
  ausentes e ambíguos, datas incoerentes e quantidades incompatíveis.
- **Controle da carga:** transação única, rollback integral em erro, SHA-256,
  repetição sem duplicação e preservação de extras e registros originais.
- **Teste da trigger:** gerar chave e fornecedor na mesma transação, manter
  fornecedor informado, rejeitar FK inexistente e testar sessões concorrentes.
- **Aceite:** cada alteração comercial deve ter fonte, responsável e decisão
  registrados. Depois da correção aprovada, executar novamente a reconciliação.

## Erros, divergências e alertas encontrados

As quantidades desta tabela consideram **todo o arquivo**, que contém janeiro,
fevereiro e março. Os números do fechamento mensal aparecem na seção seguinte.
Alertas comerciais dependem da regra do cliente e não são automaticamente
classificados como valores errados.

| Tabela/origem | Problema ou alerta | Quantidade | Consulta | Tratamento/decisão |
| --- | --- | ---: | --- | --- |
| venda | Produto/filial sem cadastro | 13 vendas, 8 códigos distintos (P21–P28) | V03 | Preservar vendas e solicitar cadastro; 6 dessas vendas são de fevereiro |
| pedido_compra | ordem_compra igual a zero | 11 | V04 | Sinalizar ORDEM_A_CONFIRMAR; obter vínculo correto |
| pedido_compra | data_entrega anterior a data_pedido | 20 | V05 | Confirmar significado e documento, sem inventar nova data |
| entradas_mercadoria | Sem pedido correspondente por ordem/produto/filial/item | 2 (NFE19, NFE20) | V06 | Validar vínculo com o cliente |
| entradas_mercadoria | Entrada anterior à data do pedido relacionado | 9 | V07 | Confrontar datas com documentos |
| pedido_compra × entradas | Quantidade entregue declarada diferente da soma das notas | 18 | V08 | Mostrar ambas as fontes e definir qual está incorreta |
| pedido_compra × entradas | Recebido acima do solicitado | 7 | V09 | Validar excesso, unidade, devolução ou ajuste |
| venda | Quantidade fracionária com unidade UN | 5 | V10 | Confirmar regra da unidade; não truncar |
| Planilha pedido_compra | Células sem cabeçalho nas linhas 22–30, colunas M–W | 9 linhas/99 células | V11 | Preservar em JSON para decisão; arquivo original intacto |
| pedido_compra × fornecedor | Referências numéricas versus códigos textuais F1...F20 | 29 referências normalizadas | V15; origem em importacao_linha.dados | Usar chave interna e codigo_origem; confirmar convenção N→F{N} |
| produtos_filial | Preço de venda menor que preço de compra | 4 | V17 | Alerta comercial, pode ser promoção ou preço desatualizado |
| pedido_compra × entradas | Custo de entrada diferente do preço de compra do pedido | 18 | V18 | Alerta de negociação/custo; validar nota e política |

V12 não retornou duplicidades de chave. V13 não retornou números negativos nem
pendência declarada negativa. V14 não retornou ambiguidade em ordens válidas.
V16 retornou zero fornecedores provisórios após a carga; os testes da trigger
foram desfeitos. As ausências de datas causadas pelo importador original foram
corrigidas pelo código, conforme os logs da Parte 1.

Não há chave única em ordem_compra isoladamente: uma ordem pode ter vários itens.
A ligação é feita por ordem_compra e protegida por produto, filial e item. Antes
de somar os recebimentos, as entradas são agregadas por essa combinação. Um
recebimento de um produto não quita os outros itens de uma mesma ordem.

## Resultados para apresentação

| Indicador de fevereiro/2025 | Resultado confirmado nos dois bancos |
| --- | ---: |
| Registros de venda | 14 |
| Quantidade vendida, preservando a precisão da origem | 173,2200 |
| Valor antes do arredondamento | 14.093,17040000 |
| Valor apresentado em reais | R$ 14.093,17 |
| Filial 1 | 13 vendas; quantidade 170,2200; R$ 13.545,64 |
| Filial 2 | 1 venda; quantidade 3,0000; R$ 547,53 |
| Produtos requisitados em mais de 10 pedidos distintos no mês | 0 |

No conjunto inteiro, a Parte 2 retorna **11 pedidos sem recebimento comprovado**,
todos com ordem zero e, por isso, **a confirmar**. Não é possível concluir que
nunca houve recebimento físico. Também retorna **10 pedidos parciais**; 7 tiveram
recebimento acima do solicitado e 1 recebeu exatamente o solicitado, totalizando
os 29 pedidos. V20 retorna 21 linhas com saldo positivo ou ordem a confirmar na
posição até fevereiro; não confundir esse indicador com o recorte de todas as datas.

Exemplo para explicar ao cliente: o pedido 1 solicita 96 unidades, declara 10
entregues, mas a entrada vinculada registra 77. O saldo declarado é 86, enquanto
o saldo pelas entradas é 19. O sistema mostra a divergência; não escolhe uma
quantidade arbitrariamente para fazer os números coincidirem.

A lista completa de resultados de V01–V21 está em
[validacao_postgres.json](evidencias/validacao_postgres.json) e
[validacao_mysql.json](evidencias/validacao_mysql.json). Diferenças de representação
JSON/TIME e de casas decimais entre drivers não alteram os valores de negócio.

## Pendências, responsabilidades e aceite

| Pendência | Responsável a definir na reunião | Evidência necessária | Condição de encerramento |
| --- | --- | --- | --- |
| Produtos/filiais ausentes | Cadastro mestre | Cadastro confirmado pelo cliente | Resolver V03 sem fabricar atributos |
| Ordens zero e entradas não vinculadas | Compras/recebimento | Pedido e nota de origem | Resolver V04/V06 e rever pendências |
| Datas e quantidades divergentes | Compras/recebimento | Documentos e significado dos campos | Aprovar ajustes e repetir V05–V09 |
| UN fracionária e preços | Comercial/estoque | Regra de unidade e histórico de preços | Justificar ou corrigir V10/V17/V18 |
| Mapeamento de fornecedor e extras | Responsável pela planilha | Confirmação de N→F{N} e conteúdo M:W | Homologar regra e destino das células |

Não houve reunião real com o cliente: não se registra aceite fictício. A carga
está tecnicamente conferida e as pendências estão rastreáveis. Para uma base
operacional definitiva, é necessário sanear esses pontos e então ativar as FKs
entre movimentos, produtos e pedidos. Os originais devem permanecer arquivados,
e toda correção aprovada deve ser documentada com comparação antes/depois.
