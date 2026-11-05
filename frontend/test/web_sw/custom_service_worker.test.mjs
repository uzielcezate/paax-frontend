// Behavioural tests for frontend/web/custom_service_worker.js.
//
// The worker is executed inside a sandbox that fakes the ServiceWorker
// globals (self, caches, fetch, clients) and dispatches real install /
// activate / fetch events, so these tests exercise what the worker DOES,
// not what its source contains.
//
// Run:  node --test frontend/test/web_sw/
// (Node >= 20; lives under test/, never under web/, because everything in
//  web/ is copied into the Flutter build output.)

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import vm from 'node:vm';

// PAAX_SW_PATH lets the suite be pointed at another worker build (e.g. the
// v1 worker) to prove the tests detect the defect.
const SW_PATH = process.env.PAAX_SW_PATH
  || resolve(dirname(fileURLToPath(import.meta.url)), '../../web/custom_service_worker.js');
const SW_SOURCE = readFileSync(SW_PATH, 'utf8');
const SW_URL = 'https://demo.example/custom_service_worker.js';
const ORIGIN = 'https://demo.example';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

function html(body = '<!doctype html><title>Paax</title>', extra = {}) {
  const r = new Response(body, { status: 200, headers: { 'content-type': 'text/html; charset=utf-8' } });
  return markResponse(r, extra);
}
function js(body = 'console.log(1)', extra = {}) {
  const r = new Response(body, { status: 200, headers: { 'content-type': 'application/javascript' } });
  return markResponse(r, extra);
}
// Response.redirected / type are read-only getters; model them per instance
// (a Response obtained through a 308 has redirected === true in browsers).
function markResponse(r, { redirected = false, type = 'basic' } = {}) {
  Object.defineProperty(r, 'redirected', { value: redirected, configurable: true });
  Object.defineProperty(r, 'type', { value: type, configurable: true });
  const origClone = r.clone.bind(r);
  r.clone = () => markResponse(origClone(), { redirected, type });
  return r;
}
function redirectedHtml() { return html('<!doctype html>', { redirected: true }); }
function opaque() {
  const r = new Response(null, { status: 200 });
  Object.defineProperty(r, 'ok', { value: false });
  Object.defineProperty(r, 'status', { value: 0 });
  return markResponse(r, { type: 'opaque' });
}

function keyOf(req) {
  const u = typeof req === 'string' ? req : req.url;
  return new URL(u, SW_URL).href;
}

class FakeCache {
  constructor(fetchImpl) { this.store = new Map(); this.fetchImpl = fetchImpl; }
  async match(req) { return this.store.get(keyOf(req)); }
  async put(req, res) { this.store.set(keyOf(req), res); }
  // Cache.add/addAll follow redirects and store the final (redirected)
  // response — exactly how the v1 worker poisoned its shell entry.
  async add(req) {
    const res = await this.fetchImpl(req, { redirect: 'follow' });
    if (!res.ok) throw new TypeError('Request failed');
    await this.put(req, res);
  }
  async addAll(reqs) { for (const r of reqs) await this.add(r); }
  async delete(req) { return this.store.delete(keyOf(req)); }
  async keys() { return [...this.store.keys()]; }
}
class FakeCacheStorage {
  constructor() { this.caches = new Map(); this.fetchImpl = null; }
  async open(name) { if (!this.caches.has(name)) this.caches.set(name, new FakeCache(this.fetchImpl)); return this.caches.get(name); }
  async keys() { return [...this.caches.keys()]; }
  async delete(name) { return this.caches.delete(name); }
  async match(req) { for (const c of this.caches.values()) { const m = await c.match(req); if (m) return m; } return undefined; }
}

class FakeEvent {
  constructor(request) { this.request = request; this.waits = []; this.response = undefined; }
  waitUntil(p) { this.waits.push(Promise.resolve(p).catch(() => {})); }
  respondWith(p) { this.response = Promise.resolve(p); }
  async settle() { await Promise.all(this.waits); }
}

function navRequest(path) {
  return { url: ORIGIN + path, method: 'GET', mode: 'navigate', redirect: 'manual' };
}
function getRequest(path) {
  return { url: ORIGIN + path, method: 'GET', mode: 'no-cors', redirect: 'follow' };
}

// `routes` maps absolute URL -> () => Response | Error. Unknown URL -> 404.
function makeWorker(routes, { initialCaches } = {}) {
  const cacheStorage = new FakeCacheStorage();
  const fetchLog = [];
  const fetchImpl = async (input, init) => {
    const url = keyOf(input);
    fetchLog.push({ url, init });
    const route = routes[url];
    if (!route) return markResponse(new Response('not found', { status: 404 }));
    const out = route(input, init);
    if (out instanceof Error) throw out;
    return out;
  };
  cacheStorage.fetchImpl = fetchImpl;
  if (initialCaches) {
    for (const [name, entries] of Object.entries(initialCaches)) {
      cacheStorage.caches.set(name, new FakeCache(fetchImpl));
      for (const [url, res] of Object.entries(entries)) cacheStorage.caches.get(name).store.set(keyOf(url), res);
    }
  }
  const listeners = {};
  const self = {
    addEventListener: (type, fn) => { (listeners[type] ||= []).push(fn); },
    skipWaiting: () => { self.skipped = true; },
    clients: { claim: async () => { self.claimed = true; } },
    registration: { scope: ORIGIN + '/' },
    location: { href: SW_URL },
  };
  const sandbox = {
    self, caches: cacheStorage, fetch: fetchImpl, URL, Response, Headers, Promise,
    console: { log() {}, warn() {}, error() {} },
    setTimeout,
  };
  sandbox.globalThis = sandbox;
  vm.runInNewContext(SW_SOURCE, sandbox, { filename: 'custom_service_worker.js' });

  async function dispatch(type, request) {
    const ev = new FakeEvent(request);
    for (const fn of listeners[type] || []) fn(ev);
    const response = ev.response === undefined ? undefined : await ev.response;
    await ev.settle();
    return { ev, response };
  }
  return {
    cacheStorage, fetchLog, self,
    install: () => dispatch('install'),
    activate: () => dispatch('activate'),
    fetch: (request) => dispatch('fetch', request),
    cache: async (name = 'paax-app-shell-v2') => cacheStorage.open(name),
  };
}

// Cloudflare Pages-like origin: `/index.html` canonicalised to `/`, so a
// fetch of /index.html (redirect: follow) yields a response flagged
// `redirected === true` whose final URL is the root.
function pagesRoutes(overrides = {}) {
  return {
    [ORIGIN + '/']: () => html(),
    [ORIGIN + '/index.html']: () => redirectedHtml(),
    [ORIGIN + '/manifest.json']: () => markResponse(new Response('{}', { status: 200, headers: { 'content-type': 'application/json' } })),
    [ORIGIN + '/flutter.js']: () => js(),
    [ORIGIN + '/flutter_bootstrap.js']: () => js(),
    [ORIGIN + '/main.dart.js']: () => js('main'),
    [ORIGIN + '/favicon.png']: () => markResponse(new Response('png', { status: 200 })),
    [ORIGIN + '/icons/Icon-192.png']: () => markResponse(new Response('png', { status: 200 })),
    [ORIGIN + '/icons/Icon-512.png']: () => markResponse(new Response('png', { status: 200 })),
    [ORIGIN + '/icons/Icon-maskable-192.png']: () => markResponse(new Response('png', { status: 200 })),
    [ORIGIN + '/icons/Icon-maskable-512.png']: () => markResponse(new Response('png', { status: 200 })),
    ...overrides,
  };
}

async function assertShellResponse(res, label) {
  assert.ok(res, `${label}: a response must be produced`);
  assert.equal(res.status, 200, `${label}: status 200`);
  assert.equal(res.redirected, false, `${label}: redirected must be false`);
  assert.match(res.headers.get('content-type'), /text\/html/, `${label}: html`);
}

// ---------------------------------------------------------------------------
// Root-cause model of the v1 worker (what the old navigation branch did)
// ---------------------------------------------------------------------------

test('root cause: a shell fetched via /index.html on a Pages-like host is a redirected response', async () => {
  const routes = pagesRoutes();
  const res = await routes[ORIGIN + '/index.html']();
  assert.equal(res.redirected, true);
  // Browsers refuse redirected responses as navigation responses from a SW,
  // so caching this entry (v1 behaviour) breaks every later navigation.
});

// ---------------------------------------------------------------------------
// Install
// ---------------------------------------------------------------------------

test('install pre-caches the canonical root shell and never /index.html', async () => {
  const w = makeWorker(pagesRoutes());
  await w.install();
  assert.equal(w.self.skipped, true, 'skipWaiting called');
  const cache = await w.cache();
  const keys = await cache.keys();
  assert.ok(keys.includes(ORIGIN + '/'), 'root shell cached');
  assert.ok(!keys.includes(ORIGIN + '/index.html'), '/index.html must not be cached');
  assert.ok(!w.fetchLog.some((f) => f.url.endsWith('/index.html')), '/index.html is never requested');
  const shell = await cache.match(ORIGIN + '/');
  await assertShellResponse(shell, 'cached shell');
  assert.ok(keys.includes(ORIGIN + '/main.dart.js'), 'main.dart.js precached');
  assert.ok(keys.includes(ORIGIN + '/flutter_bootstrap.js'), 'flutter_bootstrap.js precached');
});

test('install refuses to store a redirected, opaque or failed root response', async () => {
  for (const [label, rootRoute] of [
    ['redirected', () => redirectedHtml()],
    ['opaque', () => opaque()],
    ['500', () => markResponse(new Response('x', { status: 500, headers: { 'content-type': 'text/html' } }))],
    ['non-html', () => js()],
    ['network error', () => new TypeError('offline')],
  ]) {
    const w = makeWorker(pagesRoutes({ [ORIGIN + '/']: rootRoute }));
    await w.install();
    const cache = await w.cache();
    assert.equal(await cache.match(ORIGIN + '/'), undefined, `${label}: root not stored`);
    assert.ok((await cache.keys()).includes(ORIGIN + '/main.dart.js'), `${label}: other assets still precached`);
  }
});

test('install uses a new cache namespace (v2) so a defective v1 cache cannot be reused', async () => {
  const w = makeWorker(pagesRoutes(), {
    initialCaches: { 'paax-app-shell-v1': { [ORIGIN + '/index.html']: redirectedHtml() } },
  });
  await w.install();
  const names = await w.cacheStorage.keys();
  assert.ok(names.includes('paax-app-shell-v2'), 'v2 namespace created');
  assert.notEqual((await w.cache('paax-app-shell-v2')).store.size, 0);
});

// ---------------------------------------------------------------------------
// Activate: cleanup of obsolete caches
// ---------------------------------------------------------------------------

test('activate deletes the obsolete v1 cache, keeps v2 and claims clients', async () => {
  const w = makeWorker(pagesRoutes(), {
    initialCaches: {
      'paax-app-shell-v1': { [ORIGIN + '/index.html']: redirectedHtml() },
      'unrelated-cache': {},
    },
  });
  await w.install();
  await w.activate();
  const names = await w.cacheStorage.keys();
  assert.deepEqual(names.sort(), ['paax-app-shell-v2']);
  assert.equal(w.self.claimed, true);
});

// ---------------------------------------------------------------------------
// Navigation lifecycle
// ---------------------------------------------------------------------------

test('fresh first visit, first reload and repeated reloads all get a non-redirected HTML shell', async () => {
  const w = makeWorker(pagesRoutes());
  await w.install();
  await w.activate();
  for (let i = 0; i < 5; i++) {
    const { response } = await w.fetch(navRequest('/'));
    await assertShellResponse(response, `reload #${i}`);
  }
  // Every reload served from cache: the network was only asked for the root
  // during install + background revalidation, never for the navigation URL
  // itself with redirect semantics.
  assert.ok(w.fetchLog.every((f) => !f.url.endsWith('/index.html')));
});

test('navigation to /?demo=1, /demo and deep SPA routes serves the cached shell', async () => {
  const w = makeWorker(pagesRoutes());
  await w.install();
  await w.activate();
  for (const path of ['/?demo=1', '/demo', '/demo?demo=1', '/library/playlists/42']) {
    const before = w.fetchLog.length;
    const { response } = await w.fetch(navRequest(path));
    await assertShellResponse(response, path);
    const asked = w.fetchLog.slice(before).map((f) => f.url);
    assert.ok(!asked.some((u) => u.endsWith(path.split('?')[0]) && !u.endsWith('/')),
      `${path}: host redirect rules are not consulted for the navigation`);
  }
});

test('offline: cached shell is served when the network is down', async () => {
  const w = makeWorker(pagesRoutes());
  await w.install();
  await w.activate();
  // Same cache contents, but every network request now fails.
  const offline = makeWorker(Object.fromEntries(Object.keys(pagesRoutes()).map((k) => [k, () => new TypeError('offline')])), {
    initialCaches: { 'paax-app-shell-v2': { [ORIGIN + '/']: html(), [ORIGIN + '/main.dart.js']: js('main') } },
  });
  const nav = await offline.fetch(navRequest('/?demo=1'));
  await assertShellResponse(nav.response, 'offline navigation');
  const asset = await offline.fetch(getRequest('/main.dart.js'));
  assert.equal(await asset.response.text(), 'main', 'offline asset from cache');
});

test('offline with nothing cached falls through to the network error (no fake response)', async () => {
  const offline = makeWorker(Object.fromEntries(Object.keys(pagesRoutes()).map((k) => [k, () => new TypeError('offline')])));
  await assert.rejects(async () => { const { response } = await offline.fetch(navRequest('/')); return response; }, /offline/);
});

// ---------------------------------------------------------------------------
// Never serve a redirected response for a navigation
// ---------------------------------------------------------------------------

test('a redirected entry found in the v2 shell slot is discarded, not served', async () => {
  const w = makeWorker(pagesRoutes(), {
    initialCaches: { 'paax-app-shell-v2': { [ORIGIN + '/']: redirectedHtml() } },
  });
  const { response } = await w.fetch(navRequest('/'));
  await assertShellResponse(response, 'navigation after poisoned cache');
  const stored = await (await w.cache()).match(ORIGIN + '/');
  await assertShellResponse(stored, 'replacement stored entry');
});

test('when even the root redirects, the navigation is passed to the network and nothing is cached', async () => {
  const w = makeWorker(pagesRoutes({ [ORIGIN + '/']: () => redirectedHtml() }));
  await w.install();
  const { response } = await w.fetch(navRequest('/'));
  // Pass-through: whatever the network produced for the ORIGINAL request is
  // handed back unchanged so the browser applies its own redirect handling.
  assert.ok(response);
  assert.equal(await (await w.cache()).match(ORIGIN + '/'), undefined);
  const last = w.fetchLog[w.fetchLog.length - 1];
  assert.equal(last.url, ORIGIN + '/', 'original request forwarded');
});

test('a 200 shell served from cache is revalidated in the background and a new release replaces it', async () => {
  let version = 'v-old';
  const w = makeWorker(pagesRoutes({ [ORIGIN + '/']: () => html(`<!doctype html><!--${version}-->`) }));
  await w.install();
  await w.activate();
  version = 'v-new';
  const first = await w.fetch(navRequest('/'));
  assert.match(await first.response.text(), /v-old/, 'cache-first: old shell on this visit');
  const second = await w.fetch(navRequest('/'));
  assert.match(await second.response.text(), /v-new/, 'next visit gets the revalidated shell without clearing site data');
});

// ---------------------------------------------------------------------------
// Assets and non-navigation traffic
// ---------------------------------------------------------------------------

test('JavaScript and Flutter assets are served cache-first and updated in the background', async () => {
  let body = 'main-1';
  const w = makeWorker(pagesRoutes({ [ORIGIN + '/main.dart.js']: () => js(body) }));
  await w.install();
  await w.activate();
  body = 'main-2';
  const a = await w.fetch(getRequest('/main.dart.js'));
  assert.equal(await a.response.text(), 'main-1');
  const b = await w.fetch(getRequest('/main.dart.js'));
  assert.equal(await b.response.text(), 'main-2', 'background refresh landed');
  const boot = await w.fetch(getRequest('/flutter_bootstrap.js'));
  assert.equal(boot.response.status, 200);
  const ck = await w.fetch(getRequest('/canvaskit/canvaskit.wasm'));
  assert.equal(ck.response.status, 404, 'uncached asset goes to network');
});

test('redirected asset responses are never written to the cache', async () => {
  const w = makeWorker(pagesRoutes({ [ORIGIN + '/main.dart.js']: () => js('x', { redirected: true }) }));
  await w.install();
  await w.fetch(getRequest('/main.dart.js'));
  assert.equal(await (await w.cache()).match(ORIGIN + '/main.dart.js'), undefined);
});

test('API calls and non-GET requests are not intercepted', async () => {
  const w = makeWorker(pagesRoutes());
  await w.install();
  await w.activate();
  const api = await w.fetch({ url: 'https://api.example/v2/demo/sessions', method: 'GET', mode: 'cors' });
  assert.equal(api.response, undefined, 'GET API: not handled');
  const post = await w.fetch({ url: ORIGIN + '/', method: 'POST', mode: 'navigate' });
  assert.equal(post.response, undefined, 'POST: not handled');
});
