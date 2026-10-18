// Service worker: ให้แอปเปิดได้แม้ไม่มีอินเทอร์เน็ต (วางไฟล์นี้ไว้โฟลเดอร์เดียวกับ index.html)
const V = 'pos-v5';
const SHELL = ['./', 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/dist/umd/supabase.js'];
self.addEventListener('install', e => e.waitUntil(caches.open(V).then(c => Promise.all(SHELL.map(u => c.add(u).catch(() => {})))).then(() => self.skipWaiting())));   // โหลดไม่ได้บางไฟล์ก็ยังติดตั้งได้
self.addEventListener('activate', e => e.waitUntil(
  caches.keys().then(ks => Promise.all(ks.filter(k => k !== V).map(k => caches.delete(k)))).then(() => self.clients.claim())));
self.addEventListener('fetch', e => {
  const r = e.request; if (r.method !== 'GET') return;
  const u = new URL(r.url);
  if (u.hostname.endsWith('.supabase.co') && !u.pathname.startsWith('/storage/')) return;   // ข้อมูล/API: ใช้เครือข่ายเสมอ
  if (r.mode === 'navigate') {
    if (!/(index\.html|app\.html|\/)$/.test(u.pathname)) return;
    e.respondWith(fetch(r).then(res => { if (res.ok) { const cp = res.clone(); caches.open(V).then(c => c.put('./', cp)); } return res; })
      .catch(() => caches.match('./')));
    return;
  }
  if (r.destination === 'image' || u.pathname.includes('/storage/')) {       // รูปสินค้า: แสดงของเก่าก่อนแล้วอัปเดตเงียบๆ
    e.respondWith(caches.open(V).then(c => c.match(r).then(m => {
      const net = fetch(r).then(res => { if (res.ok) c.put(r, res.clone()); return res; }).catch(() => m);   // ไม่เก็บ 404 ไว้ (รูปที่เพิ่งอัปโหลดจะได้ขึ้นทันที)
      return m || net;
    })));
    return;
  }
  e.respondWith(caches.match(r).then(m => m || fetch(r).then(res => { if (res.ok) { const cp = res.clone(); caches.open(V).then(c => c.put(r, cp)); } return res; })));
});
