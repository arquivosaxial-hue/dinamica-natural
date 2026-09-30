-- ============================================================
-- 03 — KEEPALIVE MAIS FORTE
-- ============================================================
-- Onde rodar: Supabase → SQL Editor → New query → cole tudo → Run.
--
-- Por quê: em 30/09/2026 o Supabase avisou que o projeto seria pausado
-- por "inatividade", mesmo com o keepalive do GitHub rodando verde duas
-- vezes por semana. A varredura deles não considera uma leitura pequena
-- como atividade de verdade.
--
-- O que muda: o ping() deixa de só contar linhas e passa a GRAVAR uma
-- marca no banco (escrita = atividade que aparece no disco e no WAL).
-- No GitHub, o agendamento passa a ser diário.
-- ============================================================

create or replace function public.ping()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := now();
begin
  -- grava a marca do batimento (escrita de verdade, não só leitura)
  insert into public.configuracoes (chave, valor, atualizado_em)
  values ('ultimo_keepalive', to_char(v_agora, 'YYYY-MM-DD HH24:MI:SS UTC'), v_agora)
  on conflict (chave) do update
    set valor = excluded.valor, atualizado_em = excluded.atualizado_em;

  return 'ok ' || to_char(v_agora, 'YYYY-MM-DD HH24:MI:SS');
end $$;

grant execute on function public.ping() to anon, authenticated;

-- [CONFERIR] — rode e veja se a marca foi gravada agora
select public.ping() as resposta;
select chave, valor, atualizado_em from public.configuracoes where chave = 'ultimo_keepalive';
