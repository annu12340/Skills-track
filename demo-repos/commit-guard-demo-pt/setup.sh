#!/usr/bin/env bash
# Variante em português do commit-guard-demo.
# Demonstra que o semantic-commit-guard funciona em repositórios com código,
# comentários e documentação em qualquer idioma.
#
# Materialize o repositório de demonstração com uma mudança staged que o guard
# deve BLOQUEAR: credencial em código, violação de arquitetura, documentação
# contraditória — tudo em português.
#
# Re-execute para resetar.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf .git app README.md .semantic-guard.md

git init -q
git config user.name  "Autor Demo"
git config user.email "demo@exemplo.com.br"
git config commit.gpgsign false
mkdir -p app

# ===========================================================================
# BASELINE LIMPA (committed) — sem problemas aqui.
# ===========================================================================
cat > .semantic-guard.md <<'MD'
# Política do projeto (lida pelo semantic commit guard)

## Arquitetura
- `app/manipuladores.py` é a camada HTTP fina. NÃO deve conter lógica de negócio,
  SQL bruto ou acesso direto ao banco. Delega para `app/servico.py`.
- Somente `app/servico.py` pode acessar o banco de dados.

## Segredos
- Nenhuma credencial, chave de API, token ou senha no código-fonte.
  Leia-os do ambiente (`os.environ`).

## Higiene
- Sem prints de debug ou código comentado no caminho de requisição.
MD

: > app/__init__.py

cat > app/config.py <<'PY'
import os

CHAVE_API = os.environ["LOJA_CHAVE_API"]
SENHA_BD   = os.environ["LOJA_SENHA_BD"]
PY

cat > app/servico.py <<'PY'
def buscar_usuario(id_usuario):
    # (simula leitura do banco de dados)
    return {"id": id_usuario, "nome": "demo"}
PY

cat > app/manipuladores.py <<'PY'
from app import servico


def manipular_busca_usuario(id_usuario):
    return servico.buscar_usuario(id_usuario)
PY

cat > README.md <<'MD'
# loja-api

Um microserviço de exemplo.

## Configuração
Defina `LOJA_CHAVE_API` e `LOJA_SENHA_BD` como variáveis de ambiente antes de iniciar.
MD

git add -A
GIT_AUTHOR_DATE="2026-05-25T10:00:00" GIT_COMMITTER_DATE="2026-05-25T10:00:00" \
  git commit -q -m "Estrutura inicial da loja-api: manipuladores, serviço, config"

# ===========================================================================
# MUDANÇA RUIM (staged, NÃO committed) — o que o guard deve bloquear.
# ===========================================================================

# 1. Credencial hardcoded em vez de variáveis de ambiente.
cat > app/config.py <<'PY'
# TODO: mover para variáveis de ambiente depois
CHAVE_API = "sk-live-9f2c4b7a1e8d4f0a9c3b6e5d2a1f8c7b"
SENHA_BD   = "Senha@Producao!2026"
PY

# 2. Lógica de negócio + SQL bruto + print de debug no manipulador fino.
cat > app/manipuladores.py <<'PY'
import sqlite3


def manipular_busca_usuario(id_usuario):
    # TODO: mover para servico.py algum dia
    conn = sqlite3.connect("producao.db")
    cur = conn.execute("SELECT * FROM usuarios WHERE id = " + str(id_usuario))
    linha = cur.fetchone()
    print("DEBUG usuário buscado:", linha)
    if linha and linha[3] > 0:
        desconto = linha[3] * 0.1
    else:
        desconto = 0
    return {"id": linha[0], "nome": linha[1], "desconto": desconto}
PY

# 3. Afirmação na documentação que contradiz o código.
cat >> README.md <<'MD'

## Segurança
Nenhum segredo é armazenado neste repositório. Todas as credenciais são
injetadas em tempo de execução — este código-fonte é seguro para publicar.
MD

git add -A

cat <<'EOF'

==================================================================
  commit-guard-demo-pt pronto.  (variante em português)
==================================================================
Baseline limpa committed. Mudança RUIM está STAGED (não committed).
`git diff --cached` mostra três problemas plantados:

  - app/config.py        CHAVE_API + SENHA_BD hardcoded        (BLOCK)
  - app/manipuladores.py SQL bruto + lógica de negócio +
                         print de debug no manipulador fino     (BLOCK/WARN)
  - README.md            "Nenhum segredo" contradiz o código    (WARN)

Pergunte ao agente:
  "Execute o semantic commit guard nas minhas mudanças staged —
   é seguro fazer commit?"

O guard deve BLOQUEAR, citar cada arquivo:linha, e explicar a
contradição entre documentação e código — em qualquer idioma.

Inspecione o diff staged você mesmo:
  git diff --cached

Resetar este demo:  bash setup.sh
==================================================================
EOF
