"""Backup das tabelas da Dinâmica Natural (roda no GitHub Actions).

Lê cada tabela pela API REST com a chave de serviço, de 1000 em 1000
linhas, e grava tudo num único backup/backup-AAAA-MM-DD.json.gz.
Se alguma tabela falhar, grava o que conseguiu e SAI COM ERRO (o
workflow fica vermelho) — melhor saber do que ter backup incompleto calado.

As imagens do Storage não entram aqui (só os endereços delas).
"""
import datetime
import gzip
import json
import os
import sys
import urllib.error
import urllib.request

TABELAS = ["perfis", "categorias", "planos", "experiencias", "plano_experiencias",
           "favoritos", "configuracoes", "auditoria"]
LOTE = 1000

url = os.environ.get("SUPABASE_URL", "").rstrip("/")
chave = os.environ.get("SUPABASE_SERVICE_KEY", "")
if not url or not chave:
    print("::error::Faltam os secrets SUPABASE_URL e/ou SUPABASE_SERVICE_KEY.")
    sys.exit(1)

cab = {"apikey": chave, "Accept": "application/json"}
if chave.startswith("eyJ"):  # chave antiga (JWT) também precisa do Bearer
    cab["Authorization"] = "Bearer " + chave


def ler(tabela):
    linhas, inicio = [], 0
    while True:
        req = urllib.request.Request(
            f"{url}/rest/v1/{tabela}?select=*",
            headers={**cab, "Range-Unit": "items", "Range": f"{inicio}-{inicio + LOTE - 1}"})
        with urllib.request.urlopen(req, timeout=60) as r:
            parte = json.loads(r.read().decode("utf-8"))
        linhas += parte
        if len(parte) < LOTE:
            return linhas
        inicio += LOTE


agora = datetime.datetime.now(datetime.timezone.utc)
saida = {"gerado_em": agora.isoformat(), "tabelas": {}}
falhas = []
for t in TABELAS:
    try:
        saida["tabelas"][t] = ler(t)
        print(f"OK  {t}: {len(saida['tabelas'][t])} linhas")
    except urllib.error.HTTPError as e:
        falhas.append(t)
        print(f"ERRO {t}: HTTP {e.code} {e.read()[:200]!r}")
    except Exception as e:  # noqa: BLE001
        falhas.append(t)
        print(f"ERRO {t}: {e}")

os.makedirs("backup", exist_ok=True)
nome = f"backup/backup-{agora.date().isoformat()}.json.gz"
with gzip.open(nome, "wt", encoding="utf-8") as f:
    json.dump(saida, f, ensure_ascii=False)
print(f"Gravado {nome}")

if falhas:
    print(f"::error::Tabelas que falharam: {', '.join(falhas)}")
    sys.exit(1)
