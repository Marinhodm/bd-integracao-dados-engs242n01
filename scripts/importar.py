"""Importação transacional e auditável do Excel para PostgreSQL ou MySQL."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from collections import Counter
from datetime import date, datetime, time, timedelta
from decimal import Decimal, InvalidOperation
from pathlib import Path

from openpyxl import load_workbook
from openpyxl.utils import get_column_letter
from openpyxl.utils.datetime import CALENDAR_WINDOWS_1900, from_excel

RAIZ = Path(__file__).resolve().parents[1]
COLUNAS = {
    "fornecedor": ["idfornecedor", "razao_social"],
    "produtos_filial": ["filial_id", "idproduto", "descricao", "estoque",
                       "preco_unitario", "preco_compra", "preco_venda", "idfornecedor"],
    "pedido_compra": ["pedido_id", "data_pedido", "item", "produto_id",
                     "descricao_produto", "ordem_compra", "qtde_pedida", "filial_id",
                     "data_entrega", "qtde_entregue", "preco_compra", "fornecedor_id"],
    "entradas_mercadoria": ["data_entrada", "nro_nfe", "item", "produto_id",
                          "descricao_produto", "ordem_compra", "qtde_recebida",
                          "filial_id", "custo_unitario"],
    "venda": ["venda_id", "data_emissao", "horariomov", "produto_id", "qtde_vendida",
              "valor_unitario", "filial_id", "item", "unidade_medida"],
}
INTEIROS = {"filial_id", "pedido_id", "item", "ordem_compra", "venda_id"}
DECIMAIS = {"estoque", "preco_unitario", "preco_compra", "preco_venda",
            "qtde_pedida", "qtde_entregue", "qtde_recebida",
            "custo_unitario", "qtde_vendida", "valor_unitario"}
DATAS = {"data_pedido", "data_entrega", "data_entrada", "data_emissao"}
OPCIONAIS = {"data_entrega", "descricao_produto", "unidade_medida"}


def vazio(valor):
    return valor is None or (isinstance(valor, str) and not valor.strip())


def numero(valor):
    if isinstance(valor, bool) or vazio(valor):
        raise ValueError("número obrigatório ausente/inválido")
    try:
        resultado = Decimal(str(valor))
    except InvalidOperation as exc:
        raise ValueError(f"número inválido: {valor!r}") from exc
    if not resultado.is_finite():
        raise ValueError("NaN/infinito não são permitidos")
    return resultado


def inteiro(valor):
    resultado = numero(valor)
    if resultado != resultado.to_integral_value():
        raise ValueError(f"identificador fracionário: {valor!r}")
    return int(resultado)


def decimal_exato(valor):
    resultado = numero(valor)
    if abs(resultado) >= Decimal("100000000000000"):
        raise ValueError("valor excede NUMERIC(18,4)")
    if resultado != resultado.quantize(Decimal("0.0001")):
        raise ValueError(f"mais de quatro casas decimais: {valor!r}")
    return resultado


def excel_para_data(valor, epoch=CALENDAR_WINDOWS_1900):
    """Aceita data já convertida, serial Excel ou texto em formato explícito."""
    if vazio(valor):
        return None
    if isinstance(valor, datetime):
        return valor.date()
    if isinstance(valor, date):
        return valor
    if isinstance(valor, (int, float, Decimal)) and not isinstance(valor, bool):
        convertido = from_excel(float(numero(valor)), epoch=epoch)
        if isinstance(convertido, datetime):
            return convertido.date()
        raise ValueError(f"serial não representa uma data: {valor!r}")
    if isinstance(valor, str):
        for formato in ("%Y-%m-%d", "%d/%m/%Y"):
            try:
                return datetime.strptime(valor.strip(), formato).date()
            except ValueError:
                pass
    raise ValueError(f"data inválida: {valor!r}")


def texto(valor):
    if vazio(valor):
        raise ValueError("texto obrigatório ausente")
    return str(valor).strip()


def codigo_fornecedor(valor, numerico=False):
    # Convenção explícita deste dataset: pedido.fornecedor_id=1 refere-se a F1.
    # A existência de F1 no cadastro é verificada antes de conectar ao banco.
    return f"F{inteiro(valor)}" if numerico else texto(valor)


def converter(aba, coluna, valor, epoch):
    if vazio(valor):
        if coluna in OPCIONAIS:
            return None
        raise ValueError(f"{coluna}: campo obrigatório vazio")
    if coluna in ("idfornecedor", "fornecedor_id"):
        return codigo_fornecedor(valor, numerico=aba == "pedido_compra")
    if coluna in INTEIROS:
        return inteiro(valor)
    if coluna in DECIMAIS:
        return decimal_exato(valor)
    if coluna in DATAS:
        return excel_para_data(valor, epoch)
    if coluna == "horariomov":
        convertido = valor if isinstance(valor, time) else time.fromisoformat(texto(valor))
        if convertido.tzinfo is not None:
            raise ValueError("horário deve ser local, sem fuso")
        return convertido
    return texto(valor)


def ler_planilha(caminho):
    """Preserva inclusive células fora dos cabeçalhos; não modifica o Excel."""
    book = load_workbook(caminho, data_only=False, read_only=True)
    tabelas, origem, avisos = {}, [], []
    try:
        if set(book.sheetnames) != set(COLUNAS):
            raise ValueError(f"abas inesperadas: {book.sheetnames!r}")
        for aba, colunas in COLUNAS.items():
            ws = book[aba]
            linhas = iter(ws.iter_rows(values_only=True))
            cabecalho = next(linhas)
            nomes = [str(v).strip() if v is not None else None for v in cabecalho]
            for coluna in colunas:
                if nomes.count(coluna) != 1:
                    raise ValueError(f"{aba}: cabeçalho {coluna!r} ausente/duplicado")
            indices = {c: nomes.index(c) for c in colunas}
            tabelas[aba] = []
            for linha, valores in enumerate(linhas, start=2):
                if all(vazio(v) for v in valores):
                    continue
                dados = {c: valores[i] for c, i in indices.items()}
                extras = {get_column_letter(i + 1): v for i, v in enumerate(valores)
                          if i not in indices.values() and not vazio(v)}
                if any(isinstance(v, str) and v.startswith("=") for v in valores):
                    raise ValueError(f"{aba}, linha {linha}: fórmula exige conferência")
                try:
                    registro = {c: converter(aba, c, v, book.epoch) for c, v in dados.items()}
                except (ValueError, TypeError, OverflowError) as exc:
                    raise ValueError(f"{aba}, linha {linha}: {exc}") from exc
                if aba == "produtos_filial":
                    registro["produto_id"] = registro.pop("idproduto")
                if aba == "fornecedor":
                    registro["codigo_origem"] = registro.pop("idfornecedor")
                tabelas[aba].append(registro)
                origem.append((aba, linha, dados, extras or None))
                if extras:
                    avisos.append(f"{aba}, linha {linha}: extras preservados em {','.join(extras)}")
    finally:
        book.close()
    codigos = [r["codigo_origem"] for r in tabelas["fornecedor"]]
    if len(codigos) != len(set(codigos)):
        raise ValueError("código de fornecedor duplicado na origem")
    for aba, coluna in [("produtos_filial", "idfornecedor"), ("pedido_compra", "fornecedor_id")]:
        for r in tabelas[aba]:
            if r[coluna] not in codigos:
                raise ValueError(f"{aba}: fornecedor {r[coluna]!r} ausente no cadastro")
    return tabelas, origem, avisos


def conectar(banco):
    config = {
        "host": os.getenv("DB_HOST", "127.0.0.1"),
        "port": int(os.getenv("DB_PORT", "5432" if banco == "postgres" else "3306")),
        "user": os.getenv("DB_USER", "postgres" if banco == "postgres" else "root"),
        "password": os.getenv("DB_PASSWORD", ""),
    }
    nome = os.getenv("DB_NAME", "integracao")
    if banco == "postgres":
        import psycopg
        return psycopg.connect(**config, dbname=nome, connect_timeout=10)
    import pymysql
    return pymysql.connect(**config, database=nome, charset="utf8mb4",
                           autocommit=False, connect_timeout=10)


def contagens(cur):
    resultado = {}
    for tabela in COLUNAS:  # nomes constantes, nunca recebidos do usuário
        cur.execute(f"SELECT COUNT(*) FROM {tabela}")
        resultado[tabela] = cur.fetchone()[0]
    return resultado


def inserir(cur, tabela, registro):
    colunas = list(registro)
    sql = f"INSERT INTO {tabela} ({', '.join(colunas)}) VALUES ({', '.join(['%s'] * len(colunas))})"
    cur.execute(sql, tuple(registro[c] for c in colunas))
    if cur.rowcount != 1:
        raise RuntimeError(f"{tabela}: INSERT não confirmou uma linha")


def normalizar_banco(valor):
    # MySQL retorna TIME como timedelta; PostgreSQL retorna datetime.time.
    if isinstance(valor, timedelta):
        segundos = int(valor.total_seconds())
        return time(segundos // 3600, (segundos % 3600) // 60, segundos % 60,
                    valor.microseconds)
    return valor


def conferir_conteudo(cur, tabelas, mapa):
    for tabela, linhas in tabelas.items():
        colunas = list(linhas[0]) if linhas else []
        if not colunas:
            continue
        cur.execute(f"SELECT {', '.join(colunas)} FROM {tabela}")
        existentes = [tuple(normalizar_banco(v) for v in linha) for linha in cur.fetchall()]
        esperados = []
        for linha in linhas:
            registro = dict(linha)
            for coluna in ("idfornecedor", "fornecedor_id"):
                if coluna in registro:
                    registro[coluna] = mapa[registro[coluna]]
            esperados.append(tuple(registro[c] for c in colunas))
        if Counter(existentes) != Counter(esperados):
            raise RuntimeError(f"{tabela}: conteúdo do banco diverge da planilha")


def importar(banco, caminho, tabelas, origem):
    sha = hashlib.sha256(caminho.read_bytes()).hexdigest()
    conn = conectar(banco)
    try:
        with conn.cursor() as cur:
            if banco == "postgres":
                cur.execute("SELECT pg_advisory_xact_lock(2025112601)")
            else:
                cur.execute("SELECT GET_LOCK(CONCAT(DATABASE(), ':importacao'), 10)")
                if cur.fetchone()[0] != 1:
                    raise RuntimeError("outra importação está em andamento")
            cur.execute("SELECT sha256 FROM importacao_lote WHERE sha256 = %s", (sha,))
            repetido = cur.fetchone() is not None
            antes = contagens(cur)
            if not repetido:
                if any(antes.values()):
                    raise RuntimeError("banco já contém dados de outra carga; use um banco vazio")
                inserir(cur, "importacao_lote", {"sha256": sha, "arquivo": caminho.name})
                for registro in tabelas["fornecedor"]:
                    inserir(cur, "fornecedor", registro)
            cur.execute("SELECT codigo_origem, idfornecedor FROM fornecedor")
            mapa = dict(cur.fetchall())
            if not repetido:
                for tabela in list(COLUNAS)[1:]:
                    for registro in tabelas[tabela]:
                        dados = dict(registro)
                        for coluna in ("idfornecedor", "fornecedor_id"):
                            if coluna in dados:
                                dados[coluna] = mapa[dados[coluna]]
                        inserir(cur, tabela, dados)
                for aba, linha, dados, extras in origem:
                    inserir(cur, "importacao_linha", {
                        "sha256": sha, "aba": aba, "linha": linha,
                        "dados": json.dumps(dados, ensure_ascii=False, default=str),
                        "campos_extras": json.dumps(extras, ensure_ascii=False, default=str) if extras else None,
                    })
            depois = contagens(cur)
            if depois != {k: len(v) for k, v in tabelas.items()}:
                raise RuntimeError(f"contagens divergentes: {depois}")
            conferir_conteudo(cur, tabelas, mapa)
            cur.execute("SELECT COUNT(*) FROM importacao_linha WHERE sha256 = %s", (sha,))
            if cur.fetchone()[0] != len(origem):
                raise RuntimeError("rastreamento de origem incompleto")
        conn.commit()
        return {"sha256": sha, "banco": banco,
                "situacao": "já importado e conferido" if repetido else "importado e confirmado",
                "linhas_no_banco": depois,
                "inseridos_nesta_execucao": {k: depois[k] - antes[k] for k in depois}}
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()  # libera também GET_LOCK no MySQL


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--banco", choices=["postgres", "mysql"], default="postgres")
    parser.add_argument("--arquivo", type=Path, default=RAIZ / "dados/base_teste.xlsx")
    parser.add_argument("--validar", action="store_true", help="confere o Excel sem conectar ao banco")
    parser.add_argument("--relatorio", type=Path, help="salva o resultado em JSON")
    args = parser.parse_args()
    try:
        tabelas, origem, avisos = ler_planilha(args.arquivo)
        resultado = {"linhas_na_planilha": {k: len(v) for k, v in tabelas.items()},
                     "avisos_estrutura": avisos}
        if args.validar:
            resultado["situacao"] = "estrutura e conversões verificadas; negócio depende do SQL 04"
            resultado["sha256"] = hashlib.sha256(args.arquivo.read_bytes()).hexdigest()
        else:
            resultado.update(importar(args.banco, args.arquivo, tabelas, origem))
        saida = json.dumps(resultado, ensure_ascii=False, indent=2)
        if args.relatorio:
            args.relatorio.parent.mkdir(parents=True, exist_ok=True)
            args.relatorio.write_text(saida + "\n", encoding="utf-8")
        print(saida)
        return 0
    except Exception as exc:
        print(f"FALHA: {exc}. Nenhum sucesso de importação foi confirmado.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
