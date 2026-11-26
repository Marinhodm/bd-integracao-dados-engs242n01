# Parte 1 — implantação e importação

## Ferramentas e execução

Solução em Python 3.10+, openpyxl, psycopg 3 (PostgreSQL) e PyMySQL (MySQL).
As Partes 2, 3 e 4 usam SQL. A execução foi conferida em PostgreSQL **17.12**
e MySQL **8.4.13.1**, com bancos locais temporários e independentes. O MySQL
informa `8.4.13` em `SELECT version()`; o pacote inclui a atualização `.1`.

Na pasta do projeto, prepare as dependências no PowerShell:

```powershell
python -m venv .venv
./.venv/Scripts/python.exe -m pip install -r requirements.txt
./.venv/Scripts/python.exe scripts/importar.py --validar
```

Crie um banco vazio no servidor de sua escolha. No PostgreSQL, execute
`CREATE DATABASE integracao;` fora de uma transação. No MySQL, execute
`CREATE DATABASE integracao CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;`.
Conecte ao novo banco no DBeaver e execute o DDL correspondente:

- PostgreSQL: `sql/01_ddl_postgres.sql`.
- MySQL: `sql/01_ddl_mysql.sql`.

O DDL não apaga objetos e deve ser executado uma vez em banco vazio.
O MySQL faz commit implícito de DDL; o PostgreSQL usa BEGIN/COMMIT no arquivo.

Configure a conexão por variáveis de ambiente e importe:

```powershell
$env:DB_HOST = '127.0.0.1'
$env:DB_PORT = '5432'
$env:DB_NAME = 'integracao'
$env:DB_USER = 'postgres'
$env:DB_PASSWORD = 'SUA_SENHA_LOCAL'
./.venv/Scripts/python.exe scripts/importar.py --banco postgres --relatorio relatorios/importacao.json
```

Para MySQL, use a porta `3306`, o usuário MySQL e `--banco mysql`.
A senha acima é apenas um exemplo. Não salvar credenciais no código.
O caminho padrão da planilha é relativo ao projeto, não ao diretório do terminal.
Também é possível informar `--arquivo caminho/base_teste.xlsx`.

Depois da carga, execute `02_consultas.sql`, o `03_transformacoes.sql`
(PostgreSQL) ou `03_transformacoes_mysql.sql` (MySQL), e `04_validacao.sql`.
O arquivo MySQL da trigger deve ser executado como script, respeitando `DELIMITER`.

## Estrutura da planilha e tipos

A origem tem 122 linhas de dados, em cinco abas. As datas são células Excel
com formato de data; openpyxl/pandas já as entregam como datetime. O importador
aceita também serial Excel, date e texto YYYY-MM-DD ou DD/MM/YYYY, sem adivinhar
outros formatos. Para serial, respeita a época definida no próprio workbook.

| Aba | Colunas e tipos lidos/tratados |
| --- | --- |
| fornecedor | `idfornecedor`: texto F1...F20; `razao_social`: texto |
| produtos_filial | `filial_id`: inteiro; `idproduto`, `descricao`, `idfornecedor`: texto; `estoque`, `preco_unitario`, `preco_compra`, `preco_venda`: decimal |
| pedido_compra | `pedido_id`, `item`, `ordem_compra`, `filial_id`, `fornecedor_id`: inteiros; `produto_id`, `descricao_produto`: texto; `data_pedido`, `data_entrega`: data; `qtde_pedida`, `qtde_entregue`, `preco_compra`: decimal |
| entradas_mercadoria | `data_entrada`: data; `nro_nfe`, `produto_id`, `descricao_produto`: texto; `item`, `ordem_compra`, `filial_id`: inteiros; `qtde_recebida`, `custo_unitario`: decimal |
| venda | `venda_id`, `filial_id`, `item`: inteiros; `data_emissao`: data; `horariomov`: hora; `produto_id`, `unidade_medida`: texto; `qtde_vendida`, `valor_unitario`: decimal |

As células M:W das linhas 22:30 de pedido_compra contêm valores sem cabeçalhos
(99 células em nove linhas). Elas não são tratadas como novas colunas de negócio:
são preservadas em `importacao_linha.campos_extras`, junto da aba, linha e hash.
A planilha também tem formatação em colunas vazias; isso não cria novos registros.

## Erros do DDL e correções

Executamos o DDL original em banco separado, sem interromper após o primeiro erro.
O log está em [ddl_original_postgres.txt](evidencias/ddl_original_postgres.txt).
Somente venda e pedido_compra foram criadas nessa primeira execução.

| Tabela/ponto | Erro observado ou encontrado na revisão | Correção |
| --- | --- | --- |
| entradas_mercadoria | `column "ordem_compra" named in key does not exist` | Declarar ordem_compra |
| produtos_filial | `syntax error at or near "("` | Inserir a vírgula antes da constraint |
| produtos_filial | A chave usa idproduto, mas a coluna chama produto_id; este erro fica oculto pelo erro de sintaxe anterior | Usar produto_id na chave |
| fornecedor | `column "idproduto" named in key does not exist` | Chave primária somente no identificador do fornecedor |
| produtos/fornecedor | decricao, idfonecedor e idforncedor não correspondem ao importador | Padronizar descricao e idfornecedor |
| Tipos | IDs e valores monetários definidos como float8 | Inteiros para IDs e NUMERIC/DECIMAL(18,4) para quantidades e valores |
| Fornecedor | Origem usa códigos textuais e o PDF pede geração numérica | Chave numérica gerada e codigo_origem textual único preservado |
| Filial | Identidade de movimentos deve distinguir filiais | Incluir filial_id nas chaves de pedidos e entradas |
| Dialeto | public, casts `::`, int8/int4/float8 e IDENTITY não devem ser copiados cegamente entre bancos | Arquivos próprios PostgreSQL/MySQL; AUTO_INCREMENT no MySQL |

As quantidades fracionárias existentes são preservadas, inclusive as marcadas UN;
seu significado comercial é validado na Parte 4. Datas permanecem DATE no banco;
a formatação DD/MM/YYYY só acontece na saída das consultas.

## Reprodução do importador original

Para isolar os defeitos do script dos defeitos de criação das tabelas, aplicamos
um DDL de diagnóstico com apenas os reparos mínimos de nomes, sintaxe e tipo do
código textual de fornecedor. Ele está em
[ddl_diagnostico_importador.sql](evidencias/ddl_diagnostico_importador.sql) e **não**
é o DDL da solução. Executamos o script original do commit `6919aef` sem alterar
sua lógica, redirecionando apenas a conexão para o banco de diagnóstico.

O script terminou com código 0 e anunciou sucesso e 33 vendas inseridas, mas
`SELECT COUNT(*)` mostrou **zero vendas**. Os 29 pedidos ficaram sem data_pedido,
e as 20 entradas sem data_entrada. Evidências:
[log original](evidencias/importador_original.txt) e
[contagens reais](evidencias/importador_original_resumo.json).

| Erro do script | Efeito | Correção implementada |
| --- | --- | --- |
| int(valor) sobre datetime na conversão de datas | Exceção capturada vira NULL; venda viola NOT NULL | Tratar datetime/date antes dos seriais; data inválida gera erro com aba e linha |
| except genérico que devolve None | Oculta dados inválidos | Falha explícita, sem sucesso aparente |
| rollback por linha e commit somente no fim da aba | Um erro pode desfazer linhas anteriores daquela transação | Uma transação para todo o arquivo; qualquer erro desfaz toda a carga |
| len(df) e contador incrementado sem verificar INSERT | Total informado pode ser falso | Verificar INSERT, comparar conteúdo completo e contar no banco antes do commit |
| ON CONFLICT DO NOTHING | Pode esconder duplicatas/conflitos | Sem supressão de conflitos; repetição controlada por SHA-256 |
| Corte e renomeação por posição das 12 primeiras colunas | Ignora extras sem rastreabilidade | Cabeçalhos verificados pelo nome; extras guardados em JSON |
| Conversões para float e substituições de ausentes por zero | Risco de perda de precisão e alteração de significado | Decimal exato; campos obrigatórios inválidos interrompem a carga |
| Senha fixa no fonte | Configuração não portátil | Variáveis DB_HOST, DB_PORT, DB_NAME, DB_USER e DB_PASSWORD |
| Comentário indica porta MySQL 3006 | Orientação errada | Porta padrão correta: 3306 |

## Tratamentos e limites de negócio

- `idproduto` da aba de produtos passa a `produto_id` no banco.
- `fornecedor.idfornecedor` textual passa a `codigo_origem`. A chave interna é
  numérica, gerada pelo banco; produtos e pedidos recebem a chave por consulta
  ao mapeamento. Não se assume que a sequência interna sempre coincide com F1→1.
- Para o campo numérico fornecedor_id dos pedidos, a convenção explícita adotada
  é N→código F{N}. Todos os 29 códigos encontram cadastro. É uma regra a confirmar
  com o cliente; os valores originais permanecem em importacao_linha.dados.
- `qtde_pendente` é calculada pelo banco como qtde_pedida − qtde_entregue, mantendo
  a visão declarada no pedido. O saldo pelas notas é calculado separadamente na
  view; uma fonte não sobrescreve a outra.
- Zero em ordem_compra, datas incoerentes e produtos sem cadastro não são
  corrigidos por suposição. Movimentos permanecem na base de integração e são
  apontados nas consultas. Não criamos descrições fictícias para P21...P28.
- As FKs de fornecedores estão ativas. FKs de movimentos para produtos/pedidos
  ficam para uma etapa posterior de homologação: ativá-las agora rejeitaria os
  registros que precisam ser auditados. A base entregue é uma base de integração
  com pendências conhecidas, e não um cadastro operacional já homologado.
- `importacao_lote` guarda SHA-256/nome/data da carga; `importacao_linha` guarda
  os 122 registros de origem, inclusive extras. Somente data_entrega,
  descricao_produto e unidade_medida aceitam ausência na leitura.
- Identificadores fracionários, números não finitos, fórmulas e valores com mais
  de quatro casas decimais são rejeitados explicitamente. Não há arredondamento
  silencioso na carga. Erros estruturais não são confundidos com alertas comerciais.

A repetição do mesmo arquivo confere o conteúdo e as contagens e não reinsere
registros. Carga diferente em banco preenchido é recusada. Um bloqueio de sessão/
transação serializa importações concorrentes. Não há DELETE, TRUNCATE ou DROP de
tabelas no importador. A trigger usa a sequência/auto incremento do banco e,
quando falta fornecedor em um novo produto, cria um cadastro explicitamente
provisório. IDs fornecidos são preservados e validados pela FK.

## Conferência final

| Tabela | Planilha | Script original no DDL de diagnóstico | PostgreSQL corrigido | MySQL corrigido |
| --- | --- | --- | --- | --- |
| fornecedor | 20 | 20 | 20 | 20 |
| produtos_filial | 20 | 20 | 20 | 20 |
| pedido_compra | 29 | 29, com data_pedido NULL | 29 | 29 |
| entradas_mercadoria | 20 | 20, com data_entrada NULL | 20 | 20 |
| venda | 33 | 0 | 33 | 33 |

Os relatórios `importacao_postgres_1.json` e `importacao_mysql_1.json` registram a
primeira carga; os de sufixo `_2` registram zero novas linhas na repetição.
Em fevereiro, ambos os bancos retornaram 14 vendas, quantidade 173,2200 e valor
bruto 14.093,17040000, arredondado no total para **R$ 14.093,17**. Os 21 blocos
V01–V21 foram executados nos dois bancos, com os mesmos totais e ocorrências.

Hash da planilha preservada:
`b4083f063277b27ffbd50a5611d1514488878b896767cbf0efaeac7c6a6ba918`.

## Testes e reprodução

```powershell
# Sem banco: conversões e estrutura; testes de integração ficam desabilitados.
./.venv/Scripts/python.exe -m unittest discover -s tests -v
```

Para integração, crie bancos separados `integracao_teste` e `rollback_teste`.
Aplique o DDL nos dois; importe e execute SQLs 02 e 03 somente em integracao_teste.
Configure DB_HOST/DB_PORT/DB_USER/DB_PASSWORD e execute:

```powershell
$env:DB_NAME = 'integracao_teste'
$env:DB_ENGINE = 'postgres' # ou mysql
$env:RUN_DB_TESTS = '1'
./.venv/Scripts/python.exe -m unittest discover -s tests -v
```

Foram executados **15 testes em cada banco**, todos aprovados. Incluem datas,
valores inválidos, conteúdo divergente com mesma contagem, repetição, erro de
chave no final da carga com rollback de todas as abas, FK e trigger concorrente.
Os testes não aceitam DB_NAME sem sufixo `_teste`. Inserções temporárias são
desfeitas, mas sequências podem ficar com lacunas, comportamento normal.
Os bancos temporários desta execução usaram portas 55432/53306 e não foram
instalados como serviços. Binários, dados locais, dependências e senhas não
fazem parte do versionamento. Os logs publicados usam caminhos relativos.

## Referências técnicas

- [Tipos numéricos PostgreSQL](https://www.postgresql.org/docs/17/datatype-numeric.html).
- [Triggers PostgreSQL](https://www.postgresql.org/docs/17/plpgsql-trigger.html).
- [Triggers MySQL](https://dev.mysql.com/doc/refman/8.4/en/trigger-syntax.html).
- [Datas Excel em openpyxl](https://openpyxl.readthedocs.io/en/stable/datetime.html).
