import sys
import tempfile
import unittest
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import importar
from openpyxl import load_workbook


class ConversoesTest(unittest.TestCase):
    def test_data_do_excel_ja_convertida_nao_vira_null(self):
        self.assertEqual(importar.excel_para_data(datetime(2025, 2, 1)), date(2025, 2, 1))
        self.assertEqual(importar.excel_para_data(date(2025, 2, 1)), date(2025, 2, 1))

    def test_serial_excel_e_textos_explicitos(self):
        for valor in (45689, "2025-02-01", "01/02/2025"):
            self.assertEqual(importar.excel_para_data(valor), date(2025, 2, 1))

    def test_data_invalida_e_rejeitada(self):
        with self.assertRaises(ValueError):
            importar.excel_para_data("31/02/2025")
        self.assertIsNone(importar.excel_para_data(None))

    def test_identificador_fracionario_nao_e_truncado(self):
        with self.assertRaises(ValueError):
            importar.inteiro(2.5)

    def test_decimal_exato_sem_arredondamento_silencioso(self):
        self.assertEqual(importar.decimal_exato(3.11), Decimal("3.11"))
        for valor in ("NaN", "Infinity", "1.00001"):
            with self.assertRaises(ValueError):
                importar.decimal_exato(valor)

    def test_origem_completa_e_celulas_extras_preservadas(self):
        tabelas, origem, avisos = importar.ler_planilha(importar.RAIZ / "dados/base_teste.xlsx")
        self.assertEqual([len(tabelas[t]) for t in importar.COLUNAS], [20, 20, 29, 20, 33])
        self.assertEqual(len(origem), 122)
        self.assertEqual(len(avisos), 9)
        self.assertEqual(sum(bool(r[3]) for r in origem), 9)
        self.assertEqual(tabelas["pedido_compra"][0]["fornecedor_id"], "F1")

    def test_erro_identifica_aba_e_linha(self):
        with tempfile.TemporaryDirectory() as tmp:
            arquivo = Path(tmp) / "invalido.xlsx"
            book = load_workbook(importar.RAIZ / "dados/base_teste.xlsx")
            book["venda"]["B2"] = "31/02/2025"
            book.save(arquivo)
            book.close()
            with self.assertRaisesRegex(ValueError, "venda, linha 2"):
                importar.ler_planilha(arquivo)


if __name__ == "__main__":
    unittest.main()
