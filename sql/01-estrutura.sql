-- ============================================================
-- DINÂMICA NATURAL — Planos de Atividades Imersivas
-- 01 — ESTRUTURA COMPLETA DO BANCO (projeto novo)
-- ============================================================
-- Onde rodar: Supabase → SQL Editor → New query → cole TUDO → Run.
--
-- Este arquivo é para um projeto VAZIO. Ele cria tudo de uma vez:
-- tabelas, regras de acesso (RLS), gatilhos, o bucket de imagens e
-- as categorias iniciais. Pode rodar de novo sem estragar nada: cada
-- comando usa "if not exists" / "or replace".
--
-- O que já aprendemos nos outros apps e está aplicado aqui:
--   • Nada é apagado de verdade pelo app. Planos e experiências vão
--     para a lixeira (excluido_em). Sem policy de DELETE, o banco nega.
--     (Frota: a policy ALL/anon deixava qualquer um apagar tudo.)
--   • O visitante anônimo não lê NADA. Só quem está logado, com perfil
--     ativo. A chave pública fica no HTML — é normal —, mas sozinha ela
--     não abre dado nenhum.
--   • Quem é admin é decidido pelo BANCO, não pelo JavaScript.
--     (Trupe: regra que só existia na tela era contornável.)
--   • Funções usadas nas policies são SECURITY DEFINER com search_path
--     fixo — senão a policy de perfis consulta perfis, que dispara a
--     policy de perfis... e o Postgres entra em recursão.
--   • O bucket de imagens tem limite de tamanho e de tipo.
--     (Frota: bucket sem limite chegou a 785 MB.)
--   • Existe uma função ping() para o keepalive do GitHub.
-- ============================================================


-- ============================================================
-- 1. TABELAS
-- ============================================================

-- Perfis: 1 linha por pessoa do Auth. O id É o id do Auth.
create table if not exists public.perfis (
  id                 uuid primary key references auth.users(id) on delete cascade,
  nome               text not null default '',
  email              text not null default '',
  papel              text not null default 'participante'
                     check (papel in ('admin','participante')),
  ativo              boolean not null default true,
  pode_criar_planos  boolean not null default true,
  removido_em        timestamptz,
  criado_em          timestamptz not null default now(),
  atualizado_em      timestamptz not null default now()
);

-- Categorias: alimentam os filtros e os campos de escolha.
create table if not exists public.categorias (
  id         uuid primary key default gen_random_uuid(),
  tipo       text not null check (tipo in
             ('faixa_etaria','area','tema','duracao','local','tipo_atividade')),
  nome       text not null,
  ordem      int  not null default 0,
  ativo      boolean not null default true,
  criado_em  timestamptz not null default now(),
  unique (tipo, nome)
);

-- Planos de Atividades Imersivas.
--   oficial = true  → banco principal da Dinâmica Natural (só admin cria)
--   oficial = false → plano de um participante ("Meus Planos")
create table if not exists public.planos (
  id              uuid primary key default gen_random_uuid(),
  titulo          text not null default '',
  faixa_etaria    text not null default '',
  duracao         text not null default '',
  local           text not null default '',
  area            text not null default '',
  tema            text not null default '',
  tipo_atividade  text not null default '',
  objetivos       text not null default '',
  materiais       text not null default '',
  preparacao      text not null default '',
  desenvolvimento text not null default '',
  perguntas       text not null default '',
  observar        text not null default '',
  exploracao      text not null default '',
  registro        text not null default '',
  fechamento      text not null default '',
  imagens         jsonb not null default '[]'::jsonb,   -- [{url, path}]
  oficial         boolean not null default false,
  status          text not null default 'rascunho'
                  check (status in ('rascunho','finalizado','publicado')),
  origem_id       uuid,                                  -- copiado de qual plano
  autor_id        uuid references public.perfis(id) on delete set null default auth.uid(),
  publicado_em    timestamptz,
  excluido_em     timestamptz,
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now()
);

-- Banco de Experiências (só o admin cadastra).
create table if not exists public.experiencias (
  id              uuid primary key default gen_random_uuid(),
  titulo          text not null default '',
  objetivo        text not null default '',
  faixa_etaria    text not null default '',
  duracao         text not null default '',
  local           text not null default '',
  area            text not null default '',
  tema            text not null default '',
  tipo_atividade  text not null default '',
  materiais       text not null default '',
  procedimento    text not null default '',
  fenomeno        text not null default '',
  perguntas       text not null default '',
  seguranca       text not null default '',
  imagens         jsonb not null default '[]'::jsonb,
  status          text not null default 'rascunho'
                  check (status in ('rascunho','publicado')),
  autor_id        uuid references public.perfis(id) on delete set null default auth.uid(),
  publicado_em    timestamptz,
  excluido_em     timestamptz,
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now()
);

-- Experiências usadas como componentes de um plano.
create table if not exists public.plano_experiencias (
  plano_id        uuid not null references public.planos(id) on delete cascade,
  experiencia_id  uuid not null references public.experiencias(id) on delete cascade,
  ordem           int not null default 0,
  primary key (plano_id, experiencia_id)
);

-- Favoritos de cada pessoa.
create table if not exists public.favoritos (
  usuario_id  uuid not null default auth.uid() references public.perfis(id) on delete cascade,
  tipo        text not null check (tipo in ('plano','experiencia')),
  item_id     uuid not null,
  criado_em   timestamptz not null default now(),
  primary key (usuario_id, tipo, item_id)
);

-- Dados gerais da plataforma.
create table if not exists public.configuracoes (
  chave          text primary key,
  valor          text not null default '',
  atualizado_em  timestamptz not null default now()
);

-- Registro das alterações administrativas (só leitura para o admin).
create table if not exists public.auditoria (
  id            bigint generated always as identity primary key,
  quando        timestamptz not null default now(),
  usuario_id    uuid,
  usuario_nome  text,
  acao          text not null,
  tabela        text not null,
  registro_id   text,
  resumo        text
);

create index if not exists idx_planos_oficiais
  on public.planos (status, atualizado_em desc) where oficial and excluido_em is null;
create index if not exists idx_planos_autor
  on public.planos (autor_id, atualizado_em desc) where excluido_em is null;
create index if not exists idx_experiencias_status
  on public.experiencias (status, atualizado_em desc) where excluido_em is null;
create index if not exists idx_auditoria_quando on public.auditoria (quando desc);


-- ============================================================
-- 2. FUNÇÕES DE APOIO ÀS REGRAS DE ACESSO
-- ============================================================
create or replace function public.dn_ativo()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select ativo and removido_em is null
                   from public.perfis where id = auth.uid()), false);
$$;

create or replace function public.dn_eh_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select papel = 'admin' and ativo and removido_em is null
                   from public.perfis where id = auth.uid()), false);
$$;

create or replace function public.dn_pode_criar()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select pode_criar_planos and ativo and removido_em is null
                   from public.perfis where id = auth.uid()), false);
$$;

-- Keepalive: o GitHub chama isto 2x por semana para o Supabase não
-- pausar o projeto por inatividade. Não devolve dado nenhum.
create or replace function public.ping()
returns text language sql stable security definer set search_path = public as $$
  select 'ok ' || (select count(*) from public.categorias)::text;
$$;


-- ============================================================
-- 3. GATILHOS
-- ============================================================

-- Pessoa criada no Auth → nasce o perfil (participante, ativo).
create or replace function public.dn_novo_usuario()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.perfis (id, email, nome)
  values (new.id, coalesce(new.email,''),
          coalesce(nullif(new.raw_user_meta_data->>'nome',''), split_part(coalesce(new.email,''),'@',1)))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists dn_ao_criar_usuario on auth.users;
create trigger dn_ao_criar_usuario
  after insert on auth.users
  for each row execute function public.dn_novo_usuario();

-- E-mail trocado no Auth → acompanha no perfil.
create or replace function public.dn_email_alterado()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.email is distinct from old.email then
    update public.perfis set email = coalesce(new.email,'') where id = new.id;
  end if;
  return new;
end $$;

drop trigger if exists dn_ao_alterar_email on auth.users;
create trigger dn_ao_alterar_email
  after update of email on auth.users
  for each row execute function public.dn_email_alterado();

-- atualizado_em automático + publicado_em na primeira publicação.
create or replace function public.dn_carimbar()
returns trigger language plpgsql as $$
begin
  new.atualizado_em := now();
  if tg_table_name in ('planos','experiencias') then
    if new.status = 'publicado' and (tg_op = 'INSERT' or old.status is distinct from 'publicado') then
      new.publicado_em := now();
    end if;
  end if;
  return new;
end $$;

drop trigger if exists dn_carimbo on public.perfis;
create trigger dn_carimbo before insert or update on public.perfis
  for each row execute function public.dn_carimbar();
drop trigger if exists dn_carimbo on public.planos;
create trigger dn_carimbo before insert or update on public.planos
  for each row execute function public.dn_carimbar();
drop trigger if exists dn_carimbo on public.experiencias;
create trigger dn_carimbo before insert or update on public.experiencias
  for each row execute function public.dn_carimbar();

-- Participante não mexe no próprio papel nem se desbloqueia.
-- (Hoje ele nem tem policy de UPDATE em perfis; isto é a segunda tranca,
--  caso um dia alguém crie uma policy mais aberta sem perceber.)
create or replace function public.dn_proteger_perfil()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not public.dn_eh_admin() then
    if new.papel is distinct from old.papel
       or new.ativo is distinct from old.ativo
       or new.pode_criar_planos is distinct from old.pode_criar_planos
       or new.removido_em is distinct from old.removido_em then
      raise exception 'Somente o administrador altera permissões.';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists dn_protecao on public.perfis;
create trigger dn_protecao before update on public.perfis
  for each row execute function public.dn_proteger_perfil();

-- Registro de alterações feitas por administradores.
create or replace function public.dn_auditar()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_nome   text;
  v_resumo text;
  v_acao   text := lower(tg_op);
  v_linha  jsonb := to_jsonb(coalesce(new, old));
begin
  if not public.dn_eh_admin() then
    return coalesce(new, old);
  end if;
  select nome into v_nome from public.perfis where id = auth.uid();
  v_resumo := coalesce(v_linha->>'titulo', v_linha->>'nome', v_linha->>'chave', '');
  if tg_op = 'UPDATE' then
    if (to_jsonb(old)->>'excluido_em') is null and (v_linha->>'excluido_em') is not null then
      v_acao := 'enviou para a lixeira';
    elsif (to_jsonb(old)->>'excluido_em') is not null and (v_linha->>'excluido_em') is null then
      v_acao := 'restaurou';
    elsif (to_jsonb(old)->>'status') is distinct from (v_linha->>'status') then
      v_acao := 'status: ' || coalesce(to_jsonb(old)->>'status','') || ' → ' || coalesce(v_linha->>'status','');
    else
      v_acao := 'editou';
    end if;
  elsif tg_op = 'INSERT' then
    v_acao := 'criou';
  end if;
  insert into public.auditoria (usuario_id, usuario_nome, acao, tabela, registro_id, resumo)
  values (auth.uid(), v_nome, v_acao, tg_table_name,
          coalesce(v_linha->>'id', v_linha->>'chave'), left(v_resumo, 200));
  return coalesce(new, old);
end $$;

drop trigger if exists dn_auditoria on public.planos;
create trigger dn_auditoria after insert or update on public.planos
  for each row execute function public.dn_auditar();
drop trigger if exists dn_auditoria on public.experiencias;
create trigger dn_auditoria after insert or update on public.experiencias
  for each row execute function public.dn_auditar();
drop trigger if exists dn_auditoria on public.categorias;
create trigger dn_auditoria after insert or update on public.categorias
  for each row execute function public.dn_auditar();
drop trigger if exists dn_auditoria on public.configuracoes;
create trigger dn_auditoria after insert or update on public.configuracoes
  for each row execute function public.dn_auditar();
drop trigger if exists dn_auditoria on public.perfis;
create trigger dn_auditoria after update on public.perfis
  for each row execute function public.dn_auditar();


-- ============================================================
-- 4. PERMISSÕES (GRANTS) — explícitas, sem depender do padrão
-- ------------------------------------------------------------
-- O projeto foi criado com "Automatically expose new tables"
-- DESLIGADO: nenhuma tabela nova ganha permissão sozinha. Tudo que
-- cada papel pode fazer está escrito aqui.
--   anon          → só o ping() do keepalive
--   authenticated → o necessário para o app (e o RLS filtra as linhas)
--   service_role  → a Edge Function e o backup (ignora o RLS)
-- ============================================================
grant usage on schema public to anon, authenticated, service_role;

revoke all on all tables    in schema public from anon;
revoke all on all functions in schema public from anon;

grant all on all tables    in schema public to service_role;
grant all on all sequences in schema public to service_role;
grant execute on all functions in schema public to service_role;

grant select, insert, update on
  public.perfis, public.categorias, public.planos, public.experiencias,
  public.configuracoes, public.plano_experiencias, public.favoritos
  to authenticated;
grant delete on public.favoritos, public.plano_experiencias to authenticated;
grant select on public.auditoria to authenticated;

grant execute on function public.ping() to anon, authenticated;
grant execute on function public.dn_ativo(), public.dn_eh_admin(), public.dn_pode_criar()
  to authenticated;


-- ============================================================
-- 5. REGRAS DE ACESSO (RLS)
-- ============================================================
alter table public.perfis             enable row level security;
alter table public.categorias         enable row level security;
alter table public.planos             enable row level security;
alter table public.experiencias       enable row level security;
alter table public.plano_experiencias enable row level security;
alter table public.favoritos          enable row level security;
alter table public.configuracoes      enable row level security;
alter table public.auditoria          enable row level security;

-- perfis: cada um vê o seu; admin vê e edita todos.
-- Ninguém cria perfil pelo app (quem cria é o gatilho).
drop policy if exists perfis_ler on public.perfis;
create policy perfis_ler on public.perfis for select to authenticated
  using (id = auth.uid() or public.dn_eh_admin());
drop policy if exists perfis_admin_edita on public.perfis;
create policy perfis_admin_edita on public.perfis for update to authenticated
  using (public.dn_eh_admin()) with check (public.dn_eh_admin());

-- categorias: quem está ativo lê; admin cria e edita.
drop policy if exists categorias_ler on public.categorias;
create policy categorias_ler on public.categorias for select to authenticated
  using (public.dn_ativo());
drop policy if exists categorias_admin_cria on public.categorias;
create policy categorias_admin_cria on public.categorias for insert to authenticated
  with check (public.dn_eh_admin());
drop policy if exists categorias_admin_edita on public.categorias;
create policy categorias_admin_edita on public.categorias for update to authenticated
  using (public.dn_eh_admin()) with check (public.dn_eh_admin());

-- planos:
--   lê  → oficiais publicados; os próprios; admin lê tudo
--   cria→ participante só cria plano próprio, não-oficial, se tiver permissão
--   edita→ participante só os próprios não-oficiais; admin tudo
drop policy if exists planos_ler on public.planos;
create policy planos_ler on public.planos for select to authenticated
  using (public.dn_ativo() and (
           public.dn_eh_admin()
        or autor_id = auth.uid()
        or (oficial and status = 'publicado' and excluido_em is null)));

drop policy if exists planos_criar on public.planos;
create policy planos_criar on public.planos for insert to authenticated
  with check (
       public.dn_eh_admin()
    or (public.dn_pode_criar() and autor_id = auth.uid()
        and not oficial and status in ('rascunho','finalizado')));

drop policy if exists planos_editar on public.planos;
create policy planos_editar on public.planos for update to authenticated
  using (public.dn_eh_admin()
      or (public.dn_ativo() and autor_id = auth.uid() and not oficial))
  with check (public.dn_eh_admin()
      or (public.dn_ativo() and autor_id = auth.uid() and not oficial
          and status in ('rascunho','finalizado')));

-- experiencias: todos (ativos) leem as publicadas; só admin escreve.
drop policy if exists experiencias_ler on public.experiencias;
create policy experiencias_ler on public.experiencias for select to authenticated
  using (public.dn_eh_admin()
      or (public.dn_ativo() and status = 'publicado' and excluido_em is null));
drop policy if exists experiencias_admin_cria on public.experiencias;
create policy experiencias_admin_cria on public.experiencias for insert to authenticated
  with check (public.dn_eh_admin());
drop policy if exists experiencias_admin_edita on public.experiencias;
create policy experiencias_admin_edita on public.experiencias for update to authenticated
  using (public.dn_eh_admin()) with check (public.dn_eh_admin());

-- plano_experiencias: segue o plano (a subconsulta já passa pelo RLS de planos).
drop policy if exists pe_ler on public.plano_experiencias;
create policy pe_ler on public.plano_experiencias for select to authenticated
  using (exists (select 1 from public.planos p where p.id = plano_id));
drop policy if exists pe_criar on public.plano_experiencias;
create policy pe_criar on public.plano_experiencias for insert to authenticated
  with check (exists (select 1 from public.planos p where p.id = plano_id
              and (public.dn_eh_admin() or (p.autor_id = auth.uid() and not p.oficial))));
drop policy if exists pe_apagar on public.plano_experiencias;
create policy pe_apagar on public.plano_experiencias for delete to authenticated
  using (exists (select 1 from public.planos p where p.id = plano_id
         and (public.dn_eh_admin() or (p.autor_id = auth.uid() and not p.oficial))));

-- favoritos: cada um só os seus.
drop policy if exists favoritos_meus on public.favoritos;
create policy favoritos_meus on public.favoritos for all to authenticated
  using (usuario_id = auth.uid() and public.dn_ativo())
  with check (usuario_id = auth.uid() and public.dn_ativo());

-- configuracoes: ativos leem; admin grava.
drop policy if exists config_ler on public.configuracoes;
create policy config_ler on public.configuracoes for select to authenticated
  using (public.dn_ativo());
drop policy if exists config_admin_cria on public.configuracoes;
create policy config_admin_cria on public.configuracoes for insert to authenticated
  with check (public.dn_eh_admin());
drop policy if exists config_admin_edita on public.configuracoes;
create policy config_admin_edita on public.configuracoes for update to authenticated
  using (public.dn_eh_admin()) with check (public.dn_eh_admin());

-- auditoria: só o admin lê. Ninguém grava pelo app (quem grava é o gatilho).
drop policy if exists auditoria_admin_le on public.auditoria;
create policy auditoria_admin_le on public.auditoria for select to authenticated
  using (public.dn_eh_admin());


-- ============================================================
-- 6. STORAGE — bucket de imagens
-- ------------------------------------------------------------
-- Público para LEITURA (as imagens aparecem por URL), com limite:
-- 2 MB por arquivo e só imagem. O app já reduz a foto antes de enviar
-- (fica com uns 200–400 KB).
-- Pastas:  conteudo/...     → imagens do admin (planos/experiências oficiais)
--          <id da pessoa>/  → imagens dos planos de cada participante
-- ============================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('imagens', 'imagens', true, 2097152, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update
  set public = true,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists dn_imagens_enviar on storage.objects;
create policy dn_imagens_enviar on storage.objects for insert to authenticated
  with check (bucket_id = 'imagens' and (
       public.dn_eh_admin()
    or (public.dn_pode_criar() and (storage.foldername(name))[1] = auth.uid()::text)));

drop policy if exists dn_imagens_apagar on storage.objects;
create policy dn_imagens_apagar on storage.objects for delete to authenticated
  using (bucket_id = 'imagens' and (
       public.dn_eh_admin()
    or (public.dn_ativo() and (storage.foldername(name))[1] = auth.uid()::text)));

-- (o upload/remove do supabase-js precisa conseguir "ver" o próprio arquivo)
drop policy if exists dn_imagens_ler on storage.objects;
create policy dn_imagens_ler on storage.objects for select to authenticated
  using (bucket_id = 'imagens' and public.dn_ativo());


-- ============================================================
-- 7. DADOS INICIAIS (o admin edita depois pelo app)
-- ============================================================
insert into public.categorias (tipo, nome, ordem) values
  ('faixa_etaria','Educação Infantil — 0 a 3 anos',1),
  ('faixa_etaria','Educação Infantil — 4 a 5 anos',2),
  ('faixa_etaria','Fundamental I — 6 a 10 anos',3),
  ('faixa_etaria','Fundamental II — 11 a 14 anos',4),
  ('faixa_etaria','Ensino Médio',5),
  ('faixa_etaria','Adultos e famílias',6),
  ('area','Ciências Naturais',1),
  ('area','Educação Ambiental',2),
  ('duracao','Até 30 min',1),
  ('duracao','30 a 60 min',2),
  ('duracao','1 a 2 horas',3),
  ('duracao','Meio período',4),
  ('duracao','Dia inteiro',5),
  ('local','Sala',1),
  ('local','Laboratório',2),
  ('local','Jardim',3),
  ('local','Área externa',4),
  ('local','Praia',5),
  ('local','Parque',6),
  ('tipo_atividade','Investigação',1),
  ('tipo_atividade','Observação',2),
  ('tipo_atividade','Experimento',3),
  ('tipo_atividade','Brincadeira / jogo',4),
  ('tipo_atividade','Trilha / expedição',5),
  ('tipo_atividade','Arte e registro',6),
  ('tema','Água',1),
  ('tema','Solo',2),
  ('tema','Plantas',3),
  ('tema','Insetos',4),
  ('tema','Aves',5),
  ('tema','Répteis e anfíbios',6),
  ('tema','Ciclos da natureza',7)
on conflict (tipo, nome) do nothing;

insert into public.configuracoes (chave, valor) values
  ('nome_plataforma', 'Planos de Atividades Imersivas'),
  ('subtitulo',       'Conexão entre pessoas e a natureza, por meio da ciência, da experiência e da ludicidade.'),
  ('boas_vindas',     'Que bom ter você aqui! Escolha por onde começar.'),
  ('contato',         '')
on conflict (chave) do nothing;


-- ============================================================
-- 8. [CONFERIR] — rode isto no fim e veja se está tudo certo
-- ============================================================
select jsonb_pretty(jsonb_build_object(
  'tabelas_com_rls', (select jsonb_object_agg(tablename, rowsecurity)
                      from pg_tables where schemaname = 'public'),
  'policies_com_delete', (select coalesce(jsonb_agg(tablename||'.'||policyname), '[]'::jsonb)
                          from pg_policies where schemaname = 'public' and cmd in ('DELETE','ALL')),
  'categorias', (select count(*) from public.categorias),
  'bucket', (select jsonb_build_object('publico', public, 'limite', file_size_limit,
                                       'tipos', allowed_mime_types)
             from storage.buckets where id = 'imagens'),
  'ping', public.ping()
));
-- Esperado: todas as tabelas "true"; em policies_com_delete só
-- favoritos e plano_experiencias; 32 categorias; bucket com limite 2097152.
