"""Testes reais; exigem RUN_DB_TESTS=1 e banco com sufixo _teste.

Aplicar DDL, importação e SQLs 02/03 antes. O banco vazio indicado por
DB_ROLLBACK_NAME (padrão rollback_teste) precisa somente do DDL.
"""
import copy
import os
import sys
import unittest
from concurrent.futures import ThreadPoolExecutor
from decimal import Decimal
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import importar


@unittest.skipUnless(os.getenv("RUN_DB_TESTS") == "1", "banco de teste não solicitado")
class IntegracaoTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.banco = os.getenv("DB_ENGINE", "postgres")
        if not os.getenv("DB_NAME", "").endswith("_teste"):
            raise RuntimeError("testes exigem DB_NAME com sufixo _teste")
        cls.arquivo = importar.RAIZ / "dados/base_teste.xlsx"
        cls.tabelas, cls.origem, _ = importar.ler_planilha(cls.arquivo)

    def setUp(self):
        self.conn = importar.conectar(self.banco)
        self.cur = self.conn.cursor()

    def tearDown(self):
        self.conn.rollback()
        self.cur.close()
        self.conn.close()

    def test_contagens_e_fechamento_fevereiro(self):
        self.assertEqual(importar.contagens(self.cur),
                         dict(zip(importar.COLUNAS, [20, 20, 29, 20, 33])))
        self.cur.execute("""
            SELECT COUNT(*), SUM(qtde_vendida), SUM(qtde_vendida * valor_unitario)
            FROM venda WHERE data_emissao >= '2025-02-01' AND data_emissao < '2025-03-01'
        """)
        self.assertEqual(self.cur.fetchone(), (14, Decimal("173.22"), Decimal("14093.1704")))

    def test_repeticao_confere_conteudo_sem_duplicar(self):
        r = importar.importar(self.banco, self.arquivo, self.tabelas, self.origem)
        self.assertTrue(all(n == 0 for n in r["inseridos_nesta_execucao"].values()))

    def test_trigger_cria_fornecedor_provisorio_valido(self):
        self.cur.execute("""
            INSERT INTO produtos_filial (filial_id, produto_id, descricao)
            VALUES (999, 'TESTE_TRIGGER', 'Teste transacional')
        """)
        self.cur.execute("""
            SELECT f.idfornecedor, f.cadastro_provisorio, f.codigo_origem
            FROM produtos_filial p JOIN fornecedor f ON f.idfornecedor=p.idfornecedor
            WHERE p.filial_id=999 AND p.produto_id='TESTE_TRIGGER'
        """)
        identificador, provisorio, codigo = self.cur.fetchone()
        self.assertGreater(identificador, 0)
        self.assertTrue(provisorio)
        self.assertIsNone(codigo)

    def test_trigger_preserva_fornecedor_existente(self):
        self.cur.execute("SELECT idfornecedor FROM fornecedor WHERE codigo_origem='F1'")
        identificador = self.cur.fetchone()[0]
        self.cur.execute("SELECT COUNT(*) FROM fornecedor")
        antes = self.cur.fetchone()[0]
        self.cur.execute("""
            INSERT INTO produtos_filial (filial_id, produto_id, descricao, idfornecedor)
            VALUES (999, 'TESTE_EXISTENTE', 'Teste', %s)
        """, (identificador,))
        self.cur.execute("SELECT COUNT(*) FROM fornecedor")
        self.assertEqual(self.cur.fetchone()[0], antes)

    def test_fk_rejeita_fornecedor_inexistente(self):
        with self.assertRaises(Exception):
            self.cur.execute("""
                INSERT INTO produtos_filial (filial_id, produto_id, descricao, idfornecedor)
                VALUES (999, 'TESTE_FK', 'Teste', 999999999)
            """)

    def test_trigger_concorrente_nao_colide(self):
        def inserir(i):
            conn = importar.conectar(self.banco)
            try:
                with conn.cursor() as cur:
                    cur.execute("""
                        INSERT INTO produtos_filial (filial_id, produto_id, descricao)
                        VALUES (999, %s, 'Teste concorrente')
                    """, (f"CONCORRENTE_{i}",))
                    cur.execute("SELECT idfornecedor FROM produtos_filial WHERE filial_id=999 AND produto_id=%s",
                                (f"CONCORRENTE_{i}",))
                    return cur.fetchone()[0]
            finally:
                conn.rollback()
                conn.close()
        with ThreadPoolExecutor(max_workers=4) as executor:
            ids = list(executor.map(inserir, range(4)))
        self.assertEqual(len(set(ids)), 4)

    def test_erro_tardio_desfaz_toda_a_importacao(self):
        nome = os.getenv("DB_ROLLBACK_NAME", "rollback_teste")
        if not nome.endswith("_teste") or nome == os.getenv("DB_NAME"):
            self.fail("use um banco separado, vazio e com sufixo _teste")
        tabelas = copy.deepcopy(self.tabelas)
        tabelas["venda"].append(dict(tabelas["venda"][0]))  # falha apos as demais abas
        with patch.dict(os.environ, {"DB_NAME": nome}):
            conn = importar.conectar(self.banco)
            try:
                with conn.cursor() as cur:
                    self.assertTrue(all(n == 0 for n in importar.contagens(cur).values()))
            finally:
                conn.close()
            with self.assertRaises(Exception):
                importar.importar(self.banco, self.arquivo, tabelas, self.origem)
            conn = importar.conectar(self.banco)
            try:
                with conn.cursor() as cur:
                    self.assertTrue(all(n == 0 for n in importar.contagens(cur).values()))
                    cur.execute("SELECT COUNT(*) FROM importacao_lote")
                    self.assertEqual(cur.fetchone()[0], 0)
                    cur.execute("SELECT COUNT(*) FROM importacao_linha")
                    self.assertEqual(cur.fetchone()[0], 0)
            finally:
                conn.close()

    def test_divergencia_detectada_mesmo_com_contagem_igual(self):
        alteradas = copy.deepcopy(self.tabelas)
        alteradas["venda"][0]["valor_unitario"] += Decimal("0.01")
        with self.assertRaisesRegex(RuntimeError, "conteúdo do banco diverge"):
            importar.importar(self.banco, self.arquivo, alteradas, self.origem)


if __name__ == "__main__":
    unittest.main()
