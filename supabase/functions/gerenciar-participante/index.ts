// ============================================================
// Edge Function: gerenciar-participante — Dinâmica Natural
// ------------------------------------------------------------
// Só o ADMIN usa. Faz o que o navegador não pode fazer com a chave
// pública: criar login, trocar senha, bloquear/reativar e trocar e-mail.
//
// Por que não usar convite por e-mail (como no Trupe)?
//   O e-mail padrão do Supabase manda poucas mensagens por hora e o
//   convite travava ("limite de e-mails atingido"). Aqui o admin define
//   uma senha inicial e passa para a pessoa. Nenhum e-mail é enviado.
//
// Bloquear = perfil.ativo=false E "ban" no Auth. O ban impede o login
// mesmo que alguém tente pela API; o ativo=false fecha os dados no RLS.
// ============================================================
import { createClient } from 'npm:@supabase/supabase-js@2';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const BAN_LONGO = '876000h'; // ~100 anos

function resposta(corpo: unknown, status = 200) {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}
const erro = (msg: string) => resposta({ ok: false, erro: msg });

function traduzir(msg: string): string {
  const m = String(msg || '');
  if (/already been registered|already registered|exists/i.test(m)) return 'Já existe uma pessoa com este e-mail.';
  if (/password.*(short|least|characters)/i.test(m)) return 'A senha precisa ter pelo menos 8 caracteres.';
  if (/weak|pwned|leaked/i.test(m)) return 'Senha muito fraca ou conhecida. Escolha outra.';
  if (/invalid.*email|email.*invalid/i.test(m)) return 'E-mail inválido.';
  return m;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return erro('Método não permitido.');

  const url = Deno.env.get('SUPABASE_URL')!;
  // Projetos novos podem trazer só as chaves novas (sb_secret_...).
  let service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
  if (!service) {
    try { service = Object.values(JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') || '{}'))[0] as string || ''; } catch { /* segue */ }
  }
  if (!service) return erro('Chave de serviço indisponível na função.');
  const adm = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });

  // 1. Quem está chamando? Precisa ser admin ativo.
  const token = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  if (!token) return erro('Sessão ausente. Entre novamente.');
  const { data: quem, error: eQuem } = await adm.auth.getUser(token);
  if (eQuem || !quem?.user) return erro('Sessão inválida. Entre novamente.');
  const { data: perfilAdm } = await adm.from('perfis')
    .select('id,nome,papel,ativo,removido_em').eq('id', quem.user.id).maybeSingle();
  if (!perfilAdm || perfilAdm.papel !== 'admin' || !perfilAdm.ativo || perfilAdm.removido_em) {
    return erro('Apenas administradores podem fazer isto.');
  }

  let corpo: Record<string, unknown> = {};
  try { corpo = await req.json(); } catch { return erro('Pedido inválido.'); }
  const acao = String(corpo.acao || '');
  const id = String(corpo.id || '');

  async function auditar(acaoTxt: string, alvoId: string, resumo: string) {
    await adm.from('auditoria').insert({
      usuario_id: perfilAdm!.id, usuario_nome: perfilAdm!.nome,
      acao: acaoTxt, tabela: 'perfis', registro_id: alvoId, resumo: resumo.slice(0, 200),
    });
  }
  async function alvo() {
    const { data } = await adm.from('perfis').select('id,nome,email,papel').eq('id', id).maybeSingle();
    return data;
  }

  try {
    // ---------------------------------------------------------- criar
    if (acao === 'criar') {
      const email = String(corpo.email || '').trim().toLowerCase();
      const nome = String(corpo.nome || '').trim();
      const senha = String(corpo.senha || '');
      const papel = corpo.papel === 'admin' ? 'admin' : 'participante';
      const podeCriar = corpo.pode_criar_planos !== false;
      if (!nome) return erro('Informe o nome.');
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return erro('E-mail inválido.');
      if (senha.length < 8) return erro('A senha precisa ter pelo menos 8 caracteres.');

      const { data, error } = await adm.auth.admin.createUser({
        email, password: senha, email_confirm: true, user_metadata: { nome },
      });
      if (error || !data?.user) return erro(traduzir(error?.message || 'Falha ao criar.'));
      // o gatilho do banco já criou o perfil; completamos os dados
      const { error: eP } = await adm.from('perfis').upsert({
        id: data.user.id, email, nome, papel, ativo: true, pode_criar_planos: podeCriar, removido_em: null,
      });
      if (eP) return erro('Login criado, mas o perfil falhou: ' + eP.message);
      await auditar('cadastrou participante', data.user.id, `${nome} <${email}> (${papel})`);
      return resposta({ ok: true, id: data.user.id });
    }

    if (!id) return erro('Pessoa não informada.');
    const p = await alvo();
    if (!p) return erro('Pessoa não encontrada.');
    const eu = id === perfilAdm.id;

    // ---------------------------------------------------------- editar
    if (acao === 'editar') {
      const nome = String(corpo.nome ?? p.nome).trim();
      const email = String(corpo.email ?? p.email).trim().toLowerCase();
      const papel = corpo.papel === 'admin' ? 'admin' : (corpo.papel === 'participante' ? 'participante' : p.papel);
      const podeCriar = corpo.pode_criar_planos !== false;
      if (!nome) return erro('Informe o nome.');
      if (eu && papel !== 'admin') return erro('Você não pode tirar o seu próprio acesso de administrador.');
      if (email !== p.email) {
        if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return erro('E-mail inválido.');
        const { error } = await adm.auth.admin.updateUserById(id, { email, email_confirm: true });
        if (error) return erro(traduzir(error.message));
      }
      await adm.auth.admin.updateUserById(id, { user_metadata: { nome } });
      const { error: eP } = await adm.from('perfis')
        .update({ nome, email, papel, pode_criar_planos: podeCriar }).eq('id', id);
      if (eP) return erro(eP.message);
      await auditar('editou participante', id, `${nome} <${email}> (${papel})`);
      return resposta({ ok: true });
    }

    // ---------------------------------------------------------- senha
    if (acao === 'senha') {
      const senha = String(corpo.senha || '');
      if (senha.length < 8) return erro('A senha precisa ter pelo menos 8 caracteres.');
      const { error } = await adm.auth.admin.updateUserById(id, { password: senha });
      if (error) return erro(traduzir(error.message));
      await auditar('redefiniu senha', id, `${p.nome} <${p.email}>`);
      return resposta({ ok: true });
    }

    // ---------------------------------------------------------- bloquear / revogar
    if (acao === 'bloquear' || acao === 'revogar') {
      if (eu) return erro('Você não pode bloquear a si mesmo.');
      const { error } = await adm.auth.admin.updateUserById(id, { ban_duration: BAN_LONGO });
      if (error) return erro(traduzir(error.message));
      const mud: Record<string, unknown> = { ativo: false };
      if (acao === 'revogar') mud.removido_em = new Date().toISOString();
      await adm.from('perfis').update(mud).eq('id', id);
      await auditar(acao === 'revogar' ? 'revogou acesso' : 'bloqueou', id, `${p.nome} <${p.email}>`);
      return resposta({ ok: true });
    }

    // ---------------------------------------------------------- reativar
    if (acao === 'reativar') {
      const { error } = await adm.auth.admin.updateUserById(id, { ban_duration: 'none' });
      if (error) return erro(traduzir(error.message));
      await adm.from('perfis').update({ ativo: true, removido_em: null }).eq('id', id);
      await auditar('reativou', id, `${p.nome} <${p.email}>`);
      return resposta({ ok: true });
    }

    return erro('Ação desconhecida: ' + acao);
  } catch (e) {
    return erro('Erro inesperado: ' + (e instanceof Error ? e.message : String(e)));
  }
});
