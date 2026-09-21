# Dinâmica Natural — Planos de Atividades Imersivas

Webapp (PWA) para consulta, criação e gestão de Planos de Atividades Imersivas
e Experiências. Funciona no celular, tablet e computador, e pode ser instalado
na tela inicial.

## Onde fica o quê

| Caminho | O que é |
|---|---|
| `index.html` | O app inteiro (arquivo único) |
| `sw.js`, `manifest.json`, `icon-*.png`, `logo.jpg` | Instalação no celular e ícones |
| `sql/01-estrutura.sql` | Banco completo: tabelas, regras de acesso (RLS), bucket de imagens |
| `sql/02-primeiro-admin.sql` | Transforma a primeira pessoa em administrador |
| `supabase/functions/gerenciar-participante/` | Função do servidor: criar, bloquear, reativar e trocar senha de participantes |
| `.github/workflows/` | Automações: publicar o site, keepalive, conferir versão e backup |
| `scripts/backup.py` | Exportação usada pelo backup semanal |

## Regras da casa (lições dos outros apps)

- **Ao mudar o app, suba a versão nos DOIS lugares**: `APP_VERSION` no
  `index.html` e `VERSION` no `sw.js`, com o mesmo número (ex.: `v1.0.1`).
  O workflow *Conferir versão* fica vermelho se estiverem diferentes.
  A versão aparece na tela de login e em *Minha conta*.
- **Nada é apagado de verdade pelo app.** Planos e experiências vão para a
  lixeira (Painel → Planos → Lixeira) e podem ser restaurados.
- **Segurança fica no banco, não na tela.** Quem é admin, quem pode criar,
  quem está bloqueado: tudo é conferido pelo Supabase (RLS).
- **A chave `sb_secret_...` nunca vai no `index.html`.** Só no secret do
  GitHub (backup). No app vai apenas a `sb_publishable_...`.
- **Sem cadastro público.** Só o admin cria acessos (Painel → Participantes).
- Só os arquivos do app vão para o ar: o workflow *Publicar site* copia uma
  lista fixa. SQL, scripts e workflows ficam só no repositório.

## Automações (GitHub Actions)

| Workflow | Quando | Secrets/variáveis |
|---|---|---|
| Publicar site | a cada envio para `main` | — (Settings → Pages → Source: GitHub Actions) |
| Manter Supabase ativo | seg e qui, 9h | `SUPABASE_URL`, `SUPABASE_ANON_KEY` |
| Conferir versão | a cada envio + segundas | variável opcional `SITE_URL` |
| Backup semanal | domingos, 3h | `SUPABASE_URL`, `SUPABASE_SERVICE_KEY`, `BACKUP_SENHA` |

## Evoluções previstas (fora do MVP)

Geração assistida de planos · exportação em PDF formatado (hoje: Imprimir →
Salvar como PDF) · compartilhamento · biblioteca de imagens · relatórios de uso
· notificações · login por nome de usuário.
