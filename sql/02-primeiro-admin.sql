-- ============================================================
-- 02 — TRANSFORMA UMA PESSOA EM ADMINISTRADOR
-- ============================================================
-- Use uma vez, para o primeiro admin. Os próximos o próprio admin
-- promove pelo app (Painel → Participantes → Editar → Papel).
--
-- Antes: Supabase → Authentication → Users → Add user → Create new user
--        (e-mail + senha, marque "Auto Confirm User").
--
-- Troque o e-mail abaixo e rode.
-- ============================================================
update public.perfis
set papel = 'admin', ativo = true, removido_em = null, nome = 'Administrador'
where lower(email) = lower('admin@dinamicanatural.com.br');

-- Confira: deve aparecer 1 linha com papel = admin.
select nome, email, papel, ativo from public.perfis order by criado_em;
