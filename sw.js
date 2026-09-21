// Service Worker — Dinâmica Natural
// Guarda o "casco" do app (HTML, ícones, bibliotecas) para abrir rápido e
// instalar no celular. NUNCA guarda as chamadas ao Supabase (dados, login,
// imagens enviadas): essas sempre vão para a rede.
//
// IMPORTANTE: ao publicar uma versão nova, troque a VERSION abaixo E a
// APP_VERSION no index.html pelo MESMO número. O GitHub confere
// (workflow "Conferir versão") e fica vermelho se estiverem diferentes.
const VERSION = 'v1.0.1';
const CACHE = 'dinamica-natural-' + VERSION;

const CASCO = [
  './',
  './manifest.json',
  './logo.jpg',
  './icon-180.png',
  './icon-192.png',
  './icon-512.png',
  './icon-maskable-512.png',
  'https://unpkg.com/@supabase/supabase-js@2',
];

self.addEventListener('install', (event) => {
  // add individual tolerante: um recurso falhando não impede a instalação
  event.waitUntil(caches.open(CACHE).then((c) => Promise.allSettled(CASCO.map((u) => c.add(u)))));
  // NÃO chama skipWaiting aqui: a página mostra "Nova versão disponível"
  // e a pessoa escolhe a hora (recarregar no meio de um plano perdia texto).
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((nomes) => Promise.all(nomes.filter((n) => n !== CACHE).map((n) => caches.delete(n))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.hostname.endsWith('supabase.co') || url.hostname.endsWith('supabase.in')) return;

  // Abrir o app: rede primeiro (sempre a versão mais nova); sem internet, o cache.
  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req)
        .then((resp) => {
          const copia = resp.clone();
          caches.open(CACHE).then((c) => c.put('./', copia));
          return resp;
        })
        .catch(() => caches.match('./'))
    );
    return;
  }

  // Demais arquivos (ícones, libs, fontes): cache primeiro, atualiza por trás.
  event.respondWith(
    caches.match(req).then((guardada) => {
      const rede = fetch(req)
        .then((resp) => {
          if (resp && (resp.status === 200 || resp.type === 'opaque')) {
            const copia = resp.clone();
            caches.open(CACHE).then((c) => c.put(req, copia));
          }
          return resp;
        })
        .catch(() => guardada);
      return guardada || rede;
    })
  );
});

self.addEventListener('message', (event) => {
  if (event.data === 'SKIP_WAITING') self.skipWaiting();
});
