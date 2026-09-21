/**
 * Minimal Miniflux API v1 mock, used to verify the ported sync client
 * end-to-end without real credentials.
 *
 * Implements the subset Fluent Reader's Miniflux service touches:
 *   GET  /v1/me
 *   GET  /v1/categories
 *   GET  /v1/feeds
 *   GET  /v1/entries            (order/direction/paging + status/starred filters)
 *   PUT  /v1/entries            (204)
 *   PUT  /v1/feeds/{id}/mark-all-as-read  (204)
 *   PUT  /v1/entries/{id}/bookmark        (204)
 *
 * Every request is logged with its method, path and query so the client's
 * request shape can be checked against the API contract.
 *
 * Usage:  node mock-miniflux.js [port] [token]
 */
const http = require('http');
const url = require('url');
const crypto = require('crypto');

const PORT = parseInt(process.argv[2] || '8899', 10);
const TOKEN = process.argv[3] || 'test-token-123';

/* ------------------------------------------------------------- fixtures */

const CATEGORIES = [
  { id: 1, title: 'Tech' },
  { id: 2, title: 'News' }
];

const FEEDS = [
  {
    id: 101,
    feed_url: 'https://mock.test/tech-a.xml',
    title: 'Mock Tech A',
    category: CATEGORIES[0]
  },
  {
    id: 102,
    feed_url: 'https://mock.test/tech-b.xml',
    title: 'Mock Tech B',
    category: CATEGORIES[0]
  },
  {
    id: 103,
    feed_url: 'https://mock.test/news.xml',
    title: 'Mock News',
    category: CATEGORIES[1]
  }
];

/** 300 entries: exercises the 125-per-page walk and the id cursor. */
const ENTRIES = [];
for (let id = 1; id <= 300; id++) {
  const feed = FEEDS[id % FEEDS.length];
  const published = new Date(Date.UTC(2024, 0, 1) + id * 3600000).toISOString();
  ENTRIES.push({
    id,
    // A deterministic minority is pre-read / starred, so reconciliation has
    // something to do in both directions.
    status: id % 7 === 0 ? 'read' : 'unread',
    starred: id % 11 === 0,
    title: 'Mock entry #' + id,
    url: 'https://mock.test/post/' + id,
    published_at: published,
    created_at: published,
    content: '<p>Body of entry ' + id + '</p><img src="https://mock.test/img/' + id + '.png"/>',
    author: 'Author ' + (id % 5),
    feed
  });
}

/* ------------------------------------------------------------ behaviour */

const state = {
  /** entry id -> status, mutated by PUT /v1/entries */
  statuses: new Map(ENTRIES.map(e => [e.id, e.status])),
  starred: new Map(ENTRIES.map(e => [e.id, e.starred])),
  requests: 0
};

function log(method, pathname, query, note) {
  state.requests++;
  const q = query && Object.keys(query).length ? '?' + new URLSearchParams(query) : '';
  console.log(
    new Date().toISOString().slice(11, 19) + ' [' + String(state.requests).padStart(3, ' ') + '] ' +
    method + ' ' + pathname + q +
    (note ? '   -> ' + note : '')
  );
}

function sendJson(res, code, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(code, {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(body)
  });
  res.end(body);
}

function sendEmpty(res, code) {
  res.writeHead(code, { 'Content-Length': 0 });
  res.end();
}

function authorized(req) {
  const token = req.headers['x-auth-token'];
  if (token === TOKEN) return true;
  const auth = req.headers['authorization'] || '';
  if (auth.startsWith('Basic ')) {
    const decoded = Buffer.from(auth.slice(6), 'base64').toString('utf8');
    return decoded === 'tester:secret';
  }
  return false;
}

function readBody(req) {
  return new Promise(resolve => {
    let raw = '';
    req.on('data', c => (raw += c));
    req.on('end', () => resolve(raw));
  });
}

function projectEntry(entry) {
  return Object.assign({}, entry, {
    status: state.statuses.get(entry.id),
    starred: state.starred.get(entry.id)
  });
}

/* ------------------------------------------------- Google Reader API ---- */

const GR_AUTH_TOKEN = 'gr-session-token-abc';
const GR_READ_TAG = 'user/-/state/com.google/read';
const GR_STAR_TAG = 'user/-/state/com.google/starred';
const GR_ALL_TAG = 'user/-/state/com.google/reading-list';

const GR_SUBSCRIPTIONS = [
  {
    id: 'feed/https://mock.test/gr-tech.xml',
    title: 'GR Tech',
    url: 'https://mock.test/gr-tech.xml',
    htmlUrl: 'https://mock.test/gr-tech',
    categories: [{ id: 'user/-/label/Tech', label: 'Tech' }]
  },
  {
    id: 'feed/https://mock.test/gr-news.xml',
    title: 'GR News',
    url: 'https://mock.test/gr-news.xml',
    htmlUrl: 'https://mock.test/gr-news',
    categories: [{ id: 'user/-/label/News', label: 'News' }]
  }
];

/**
 * Test knob: shift every Google Reader entry id by this amount. Simulates a
 * service that renumbered its entries, which forces a client whose cursor has
 * already advanced to re-ingest the archive.
 */
const GR_ID_OFFSET = parseInt(process.env.GR_ID_OFFSET || '0', 10);

function grItemId(n) {
  return 'tag:google.com,2005:reader/item/'
    + (n + GR_ID_OFFSET).toString(16).padStart(16, '0');
}

/**
 * Test knob: append this many extra entries (ids above the base archive) in
 * the SAME id space. Newer ids also get later publish dates, so they arrive
 * through the normal "older than" cursor without disturbing reconciliation of
 * entries the client already has.
 */
const GR_EXTRA = parseInt(process.env.GR_EXTRA || '0', 10);
const GR_COUNT = 300 + GR_EXTRA;

/**
 * Upper bound on a Google Reader id page. A real server honours `n`; set
 * GR_PAGE lower to emulate a server that pages smaller than requested.
 */
const GR_PAGE_CAP = parseInt(process.env.GR_PAGE || '1000', 10);

/**
 * Artificial latency per request, in milliseconds.
 *
 * Timing-dependent client behaviour — the fetch progress bar, the fetching
 * state, anything that is only on screen while a request is in flight — cannot
 * be observed against a localhost server that answers in a few milliseconds.
 * This knob exists so those states can be held open long enough to inspect.
 * Default 0: normal runs are unaffected.
 */
const DELAY_MS = parseInt(process.env.MOCK_DELAY_MS || '0', 10);

/** 300 entries; #300 carries an Inoreader-style ad block for strip testing. */
const GR_ENTRIES = [];
for (let n = 1; n <= GR_COUNT; n++) {
  const sub = GR_SUBSCRIPTIONS[n % GR_SUBSCRIPTIONS.length];
  const published = Math.floor(Date.UTC(2024, 0, 1) / 1000) + n * 3600;
  const categories = [GR_ALL_TAG];
  if (n % 7 === 0) categories.push(GR_READ_TAG);
  if (n % 11 === 0) categories.push(GR_STAR_TAG);

  const body = n === 300
    ? '<div>Ads from Inoreader</div><p>Real body of GR entry ' + n + '</p>'
    : '<p>Body of GR entry ' + n + '</p>';

  GR_ENTRIES.push({
    // #299 carries an HTML entity in the title: Inoreader titles arrive
    // entity-encoded and the client decodes them, GReader titles do not.
    id: grItemId(n),
    title: n === 299 ? 'GR entry &amp; #299' : 'GR entry #' + n,
    published,
    crawlTimeMsec: String(published * 1000),
    author: 'GR Author ' + (n % 4),
    summary: { content: body, direction: 'ltr' },
    canonical: [{ href: 'https://mock.test/gr-post/' + n }],
    alternate: [{ href: 'https://mock.test/gr-post/' + n }],
    origin: { streamId: sub.id, title: sub.title, htmlUrl: sub.htmlUrl },
    categories
  });
}

const grState = {
  read: new Set(GR_ENTRIES.filter(e => e.categories.includes(GR_READ_TAG)).map(e => e.id)),
  starred: new Set(GR_ENTRIES.filter(e => e.categories.includes(GR_STAR_TAG)).map(e => e.id))
};

function grAuthorized(req) {
  const auth = req.headers['authorization'] || '';
  return auth === 'GoogleLogin auth=' + GR_AUTH_TOKEN;
}

function grProject(entry) {
  const categories = [GR_ALL_TAG];
  if (grState.read.has(entry.id)) categories.push(GR_READ_TAG);
  if (grState.starred.has(entry.id)) categories.push(GR_STAR_TAG);
  return Object.assign({}, entry, { categories });
}

function parseForm(raw) {
  const out = new Map();
  for (const pair of raw.split('&')) {
    if (!pair) continue;
    const idx = pair.indexOf('=');
    const k = decodeURIComponent(idx < 0 ? pair : pair.slice(0, idx));
    const v = decodeURIComponent(idx < 0 ? '' : pair.slice(idx + 1));
    if (!out.has(k)) out.set(k, []);
    out.get(k).push(v);
  }
  return out;
}

/**
 * Google Reader routes. Returns true when the request was handled.
 */
async function handleGReader(req, res, pathname, query) {
  // ClientLogin issues the session token.
  if (pathname === '/accounts/ClientLogin') {
    const raw = await readBody(req);
    const form = parseForm(raw);
    const email = (form.get('Email') || [''])[0];
    const passwd = (form.get('Passwd') || [''])[0];
    if (email === 'reader@mock.test' && passwd === 'gr-secret') {
      log(req.method, pathname, query, '200 Auth issued');
      res.writeHead(200, { 'Content-Type': 'text/plain' });
      return res.end('SID= sid\nLSID= lsid\nAuth=' + GR_AUTH_TOKEN + '\n');
    }
    log(req.method, pathname, query, '403 bad credentials');
    res.writeHead(403, { 'Content-Type': 'text/plain' });
    return res.end('Error=BadAuthentication\n');
  }

  if (!grAuthorized(req)) {
    log(req.method, pathname, query, '401 unauthorized');
    return sendJson(res, 401, { error: 'unauthorized' });
  }

  if (pathname === '/reader/api/0/user-info') {
    // Inoreader requires the AppId/AppKey pair; surface whether it was sent.
    const appId = req.headers['appid'];
    log(req.method, pathname, query,
      '200 ok' + (appId ? '  AppId=' + appId : '  (no AppId header)'));
    return sendJson(res, 200, { userId: '1', userName: 'reader' });
  }

  if (pathname === '/reader/api/0/subscription/list') {
    log(req.method, pathname, query, GR_SUBSCRIPTIONS.length + ' subscriptions');
    return sendJson(res, 200, { subscriptions: GR_SUBSCRIPTIONS });
  }

  if (pathname === '/reader/api/0/stream/items/ids') {
    let rows = GR_ENTRIES.map(grProject);

    // `s=<stream>` selects a stream; `xt=` excludes; `it=` includes.
    if (query.s) {
      rows = rows.filter(e => e.categories.includes(query.s));
    }
    if (query.xt) {
      rows = rows.filter(e => !e.categories.includes(query.xt));
    }
    if (query.it) {
      rows = rows.filter(e => e.categories.includes(query.it));
    }

    // Page size honours `n`, as a real server does. GR_PAGE caps it lower to
    // reproduce a server whose pages are smaller than requested — the client
    // must still follow the continuation token rather than trusting page size.
    const requested = parseInt(query.n || '1000', 10);
    const pageSize = Math.max(1, Math.min(requested, GR_PAGE_CAP));
    const offset = query.c ? parseInt(query.c, 10) : 0;
    const total = rows.length;
    const page = rows.slice(offset, offset + pageSize);
    const nextOffset = offset + pageSize;
    const continuation = nextOffset < total ? String(nextOffset) : undefined;

    log(req.method, pathname, query,
      page.length + ' refs of ' + total + (continuation ? ' (more)' : ' (end)'));

    const payload = { itemRefs: page.map(e => ({ id: e.id })) };
    if (continuation) payload.continuation = continuation;
    return sendJson(res, 200, payload);
  }

  if (pathname === '/reader/api/0/stream/contents') {
    let rows = GR_ENTRIES.map(grProject);

    // `ot` = older than (seconds). The client walks newest-first via `c`.
    // IGNORE_OT=1 replays the whole archive, which is useful when the client
    // has already advanced its cursor past content that was deleted locally.
    if (query.ot && process.env.IGNORE_OT !== '1') {
      rows = rows.filter(e => e.published > Number(query.ot));
    }
    rows.sort((a, b) => b.published - a.published);

    const PAGE = 100;
    let offset = query.c ? parseInt(query.c, 10) : 0;
    const total = rows.length;
    const limit = Math.min(parseInt(query.n || '100', 10), PAGE);
    const page = rows.slice(offset, offset + limit);
    const nextOffset = offset + limit;
    const continuation = nextOffset < total ? String(nextOffset) : undefined;

    log(req.method, pathname, query,
      page.length + ' items of ' + total + (continuation ? ' (more)' : ' (end)'));

    const payload = { id: 'user/-/state/com.google/reading-list', items: page };
    if (continuation) payload.continuation = continuation;
    return sendJson(res, 200, payload);
  }

  if (pathname === '/reader/api/0/edit-tag' && req.method === 'POST') {
    const raw = await readBody(req);
    const form = parseForm(raw);
    const ids = form.get('i') || [];
    const added = form.get('a') || [];
    const removed = form.get('r') || [];

    for (const id of ids) {
      if (added.includes(GR_READ_TAG)) grState.read.add(id);
      if (removed.includes(GR_READ_TAG)) grState.read.delete(id);
      if (added.includes(GR_STAR_TAG)) grState.starred.add(id);
      if (removed.includes(GR_STAR_TAG)) grState.starred.delete(id);
    }
    log(req.method, pathname, query,
      ids.length + ' refs  add=[' + added.join(',') + '] remove=[' + removed.join(',') + ']');
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    return res.end('OK');
  }

  if (pathname === '/reader/api/0/mark-all-as-read' && req.method === 'POST') {
    const raw = await readBody(req);
    const form = parseForm(raw);
    const stream = (form.get('s') || [''])[0];
    let count = 0;
    for (const entry of GR_ENTRIES) {
      if (entry.origin.streamId === stream && !grState.read.has(entry.id)) {
        grState.read.add(entry.id);
        count++;
      }
    }
    log(req.method, pathname, query, stream + ': ' + count + ' marked read');
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    return res.end('OK');
  }

  log(req.method, pathname, query, '404 not found');
  return sendJson(res, 404, { error: 'Not found: ' + pathname });
}

/* --------------------------------------------------------------- router */

/**
 * "Load full content" fixtures. The feed's items link to HTML pages this same
 * server hosts, so the extractor can be exercised end to end on a device that
 * has no internet access. Each page carries the chrome the extractor is
 * supposed to drop (nav, header, aside, footer, script, style) and three
 * paragraphs that it must keep.
 */
const ARTICLE_BASE = 'http://127.0.0.1:' + PORT;

function localFeedXml() {
  const items = [1, 2, 3].map(n => `
    <item>
      <title>Full text fixture ${n}</title>
      <link>${ARTICLE_BASE}/article/${n}</link>
      <guid>local-full-${n}</guid>
      <pubDate>${new Date(Date.UTC(2024, 5, n, 9, 0, 0)).toUTCString()}</pubDate>
      <description><![CDATA[<p>Feed summary for fixture ${n}, deliberately much shorter than the page body so that loading the full content is visibly different.</p>]]></description>
    </item>`).join('');

  return `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Local Full Text</title>
    <link>${ARTICLE_BASE}/</link>
    <description>Full-content extraction fixtures</description>${items}
  </channel>
</rss>`;
}

/**
 * How many items `/notify.xml` currently offers. Rising this between two fetches
 * is what makes a rule-notified article genuinely new.
 */
function notifyCount() {
  return Math.max(1, parseInt(process.env.NOTIFY_COUNT || '1', 10));
}

function notifyFeedXml() {
  const items = [];
  for (let n = 1; n <= notifyCount(); n++) {
    items.push(`
    <item>
      <title>Notify fixture ${n}</title>
      <link>${ARTICLE_BASE}/article/${n}</link>
      <guid>notify-fixture-${n}</guid>
      <pubDate>${new Date(Date.UTC(2024, 6, n, 9, 0, 0)).toUTCString()}</pubDate>
      <description><![CDATA[<p>Notification fixture ${n}: the rule on this source asks to be notified.</p><img src="/img/diagram.png" alt="Fixture diagram" width="240" height="120"><p>The picture above is embedded in the feed item itself, which is how the reader gets inline images without loading the page.</p>]]></description>
    </item>`);
  }

  return `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Notify Source</title>
    <link>${ARTICLE_BASE}/</link>
    <description>Rule-notification fixtures</description>${items.join('')}
  </channel>
</rss>`;
}

/* ------------------------------------------------------- fixture images ---- */

/**
 * A real PNG of the requested size, so the reader has something it can decode
 * and so the rendered bounds can be compared against the intrinsic ratio.
 */
function pngFixture(width, height) {
  const raw = Buffer.alloc((width * 4 + 1) * height);
  for (let y = 0; y < height; y++) {
    const rowStart = y * (width * 4 + 1);
    raw[rowStart] = 0;
    for (let x = 0; x < width; x++) {
      const i = rowStart + 1 + x * 4;
      // A simple gradient, so the image is visibly not a blank rectangle.
      raw[i] = 40 + Math.round((200 * x) / width);
      raw[i + 1] = 90 + Math.round((120 * y) / height);
      raw[i + 2] = 220 - Math.round((160 * x) / width);
      raw[i + 3] = 255;
    }
  }

  const crcTable = [];
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    crcTable[n] = c >>> 0;
  }
  const crc32 = (buf) => {
    let c = 0xFFFFFFFF;
    for (let i = 0; i < buf.length; i++) c = crcTable[(c ^ buf[i]) & 0xFF] ^ (c >>> 8);
    return (c ^ 0xFFFFFFFF) >>> 0;
  };
  const chunk = (type, data) => {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length, 0);
    const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(crc32(body), 0);
    return Buffer.concat([len, body, crc]);
  };

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;   // bit depth
  ihdr[9] = 6;   // colour type: RGBA
  const signature = Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  return Buffer.concat([
    signature,
    chunk('IHDR', ihdr),
    chunk('IDAT', require('zlib').deflateSync(raw)),
    chunk('IEND', Buffer.alloc(0))
  ]);
}

const DIAGRAM_PNG = pngFixture(240, 120);

function articlePage(n) {
  const bodies = [
    `This is the first paragraph of fixture ${n}, and it exists so that the extractor has real prose to score rather than one line of placeholder text. It runs on for a couple of sentences.`,
    `The second paragraph continues the article and adds enough length for the density heuristic to accept the block. It also mentions numbers such as 42 and 7 so that it reads like ordinary writing.`,
    `A third paragraph closes the piece out, so the extracted body is clearly longer than the feed summary that was stored first. That difference is exactly what the verification compares.`
  ];
  const paragraphs = bodies.map(p => `<p>${p}</p>`).join('\n      ');

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Full text fixture ${n}</title>
  <script>window.__analytics = 'SHOULD_NOT_APPEAR';</script>
  <style>.ad { display: none; }</style>
</head>
<body>
  <nav><a href="/">Home</a><a href="/about">About us</a><a href="/pricing">Pricing plans</a></nav>
  <header><h1>Local Full Text</h1><p>Subscribe to our newsletter today</p></header>
  <main>
    <article>
      <h2>Full text fixture ${n}</h2>
      <p>${bodies[0]}</p>
      <figure>
        <img src="/img/diagram.png" alt="Fixture diagram" width="240" height="120">
        <figcaption>Fixture diagram for article ${n}</figcaption>
      </figure>
      <p>${bodies[1]}</p>
      <p>${bodies[2]}</p>
    </article>
  </main>
  <aside><h3>Related posts</h3><a href="/a">A related post with a fairly long title</a></aside>
  <footer><p>Copyright 2026 Local Full Text. All rights reserved worldwide.</p></footer>
</body>
</html>`;
}

/* ----------------------------------------------------------- Feedbin ---- */

const FEEDBIN_USER = 'fbuser';
const FEEDBIN_PASS = 'fbpass';

const FB_SUBSCRIPTIONS = [
  {
    id: 1,
    feed_id: 100,
    title: 'FB Tech',
    feed_url: 'https://mock.test/fb-tech.xml',
    site_url: 'https://mock.test/fb-tech',
    created_at: '2024-01-01T00:00:00.000000Z'
  },
  {
    id: 2,
    feed_id: 200,
    title: 'FB News',
    feed_url: 'https://mock.test/fb-news.xml',
    site_url: 'https://mock.test/fb-news',
    created_at: '2024-01-01T00:00:00.000000Z'
  }
];

/** Feedbin files a feed under a folder with a "tagging" record. */
const FB_TAGGINGS = [{ id: 1, feed_id: 100, name: 'FB Folder' }];

const FB_ENTRIES = [];
for (let i = 1; i <= 6; i++) {
  const stamp = new Date(Date.UTC(2024, 2, i, 9, 0, 0)).toISOString();
  FB_ENTRIES.push({
    id: 1000 + i,
    feed_id: i % 2 === 1 ? 100 : 200,
    title: 'FB entry #' + i,
    url: 'https://mock.test/fb-post/' + i,
    author: 'FB Author',
    content: '<p>Body of FB entry ' + i + '</p>',
    summary: 'Summary of FB entry ' + i,
    published: stamp,
    created_at: stamp
  });
}

const fbState = {
  unread: new Set(FB_ENTRIES.map(e => e.id)),
  starred: new Set([1001])
};

/* -------------------------------------------------- Nextcloud News ---- */

const NC_USER = 'ncuser';
const NC_PASS = 'ncpass';
const NC_API = '/index.php/apps/news/api/v1-3/';

const NC_FOLDERS = [{ id: 1, name: 'NC Folder' }];

const NC_FEEDS = [
  { id: 10, url: 'https://mock.test/nc-a.xml', title: 'NC Feed A', folderId: 1, added: 0 },
  { id: 20, url: 'https://mock.test/nc-b.xml', title: 'NC Feed B', folderId: 0, added: 0 }
];

const NC_ITEMS = [];
for (let i = 1; i <= 6; i++) {
  NC_ITEMS.push({
    id: 100 + i,
    guid: 'nc-guid-' + i,
    guidHash: 'hash' + i,
    url: 'https://mock.test/nc-post/' + i,
    title: 'NC item #' + i,
    author: 'NC Author',
    pubDate: Math.floor(Date.UTC(2024, 3, i, 9, 0, 0) / 1000),
    body: '<p>Body of NC item ' + i + '</p>',
    feedId: i % 2 === 1 ? 10 : 20,
    unread: true,
    starred: false,
    lastModified: 0
  });
}

function basicAuth(req, user, pass) {
  const auth = req.headers['authorization'] || '';
  if (!auth.startsWith('Basic ')) return false;
  return Buffer.from(auth.slice(6), 'base64').toString('utf8') === user + ':' + pass;
}

/** A real 1x1 PNG, so the client's decoder has something valid to decode. */
const TINY_PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  'base64');

function handleFeedbin(req, res, pathname, query) {
  if (!basicAuth(req, FEEDBIN_USER, FEEDBIN_PASS)) {
    log(req.method, pathname, query, '401 unauthorized');
    return sendJson(res, 401, { error: 'unauthorized' });
  }

  if (pathname === '/v2/authentication.json') {
    log(req.method, pathname, query, '200 ok');
    return sendJson(res, 200, { authentication: true });
  }

  if (pathname === '/v2/subscriptions.json') {
    log(req.method, pathname, query, '200 ' + FB_SUBSCRIPTIONS.length + ' subscriptions');
    return sendJson(res, 200, FB_SUBSCRIPTIONS);
  }

  if (pathname === '/v2/taggings.json') {
    log(req.method, pathname, query, '200 ' + FB_TAGGINGS.length + ' taggings');
    return sendJson(res, 200, FB_TAGGINGS);
  }

  if (pathname === '/v2/unread_entries.json' && req.method === 'GET') {
    log(req.method, pathname, query, '200 ' + fbState.unread.size + ' unread');
    return sendJson(res, 200, Array.from(fbState.unread));
  }

  if (pathname === '/v2/starred_entries.json' && req.method === 'GET') {
    log(req.method, pathname, query, '200 ' + fbState.starred.size + ' starred');
    return sendJson(res, 200, Array.from(fbState.starred));
  }

  if (pathname === '/v2/entries.json') {
    const perPage = parseInt(query.per_page || '100', 10);
    const page = parseInt(query.page || '1', 10);
    let list = FB_ENTRIES.slice();
    if (query.since) {
      const since = Date.parse(query.since);
      list = list.filter(e => Date.parse(e.created_at) > since);
    }
    list.sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at));
    const start = (page - 1) * perPage;
    const slice = list.slice(start, start + perPage);
    log(req.method, pathname, query, '200 ' + slice.length + ' of ' + list.length + ' entries'
      + (query.since ? '  since=' + query.since : ''));
    return sendJson(res, 200, slice);
  }

  const fbWrite = /^\/v2\/(unread_entries|starred_entries)(\/delete)?\.json$/.exec(pathname);
  if (fbWrite && req.method === 'POST') {
    const key = fbWrite[1] === 'starred_entries' ? 'starred_entries' : 'unread_entries';
    const removing = Boolean(fbWrite[2]);
    return readBody(req).then(raw => {
      let body = {};
      try {
        body = JSON.parse(raw);
      } catch (err) {
        log(req.method, pathname, query, '400 malformed body');
        return sendJson(res, 400, { error: 'malformed body' });
      }
      const ids = body[key] || [];
      const target = key === 'starred_entries' ? fbState.starred : fbState.unread;
      for (const id of ids) {
        if (removing) target.delete(id);
        else target.add(id);
      }
      log(req.method, pathname, query,
        (removing ? 'removed ' : 'added ') + ids.length + ' -> unread='
        + fbState.unread.size + ' starred=' + fbState.starred.size);
      return sendEmpty(res, 200);
    });
  }

  log(req.method, pathname, query, '404 not found');
  return sendJson(res, 404, { error: 'not found: ' + pathname });
}

function handleNextcloud(req, res, pathname, query) {
  if (!basicAuth(req, NC_USER, NC_PASS)) {
    log(req.method, pathname, query, '401 unauthorized');
    return sendJson(res, 401, { error: 'unauthorized' });
  }

  const route = pathname.slice(pathname.indexOf(NC_API) + NC_API.length);

  if (route === 'version') {
    log(req.method, pathname, query, '200 ok');
    return sendJson(res, 200, { version: '1.3.0', codename: 'mock' });
  }

  if (route === 'folders') {
    log(req.method, pathname, query, '200 ' + NC_FOLDERS.length + ' folders');
    return sendJson(res, 200, { folders: NC_FOLDERS });
  }

  if (route === 'feeds') {
    let newest = 0;
    for (const item of NC_ITEMS) {
      if (item.id > newest) newest = item.id;
    }
    log(req.method, pathname, query, '200 ' + NC_FEEDS.length + ' feeds');
    return sendJson(res, 200, {
      feeds: NC_FEEDS,
      starredCount: NC_ITEMS.filter(i => i.starred).length,
      newestItemId: newest
    });
  }

  if (route === 'items') {
    let batchSize = parseInt(query.batchSize || '1000', 10);
    const offset = parseInt(query.offset || '0', 10);
    const type = parseInt(query.type || '3', 10);
    const getRead = query.getRead !== 'false';

    let list = NC_ITEMS.slice();
    if (!getRead) list = list.filter(i => i.unread);
    if (type === 2) list = list.filter(i => i.starred);
    if (type === 1) list = list.filter(i => i.feedId === parseInt(query.id || '-1', 10));
    list.sort((a, b) => b.id - a.id);
    if (batchSize < 0) batchSize = list.length;

    const slice = list.slice(offset, offset + batchSize);
    log(req.method, pathname, query, '200 ' + slice.length + ' of ' + list.length + ' items');
    return sendJson(res, 200, { items: slice });
  }

  const ncItem = /^items\/(\d+)\/(read|unread|star|unstar)$/.exec(route);
  if (ncItem && req.method === 'PUT') {
    const id = Number(ncItem[1]);
    const action = ncItem[2];
    const item = NC_ITEMS.find(i => i.id === id);
    if (!item) {
      log(req.method, pathname, query, '404 no such item');
      return sendJson(res, 404, { error: 'no such item' });
    }
    if (action === 'read') item.unread = false;
    if (action === 'unread') item.unread = true;
    if (action === 'star') item.starred = true;
    if (action === 'unstar') item.starred = false;
    log(req.method, pathname, query, '200 item ' + id + ' ' + action
      + ' -> unread=' + item.unread + ' starred=' + item.starred);
    return sendEmpty(res, 200);
  }

  const ncFeed = /^feeds\/(\d+)\/read$/.exec(route);
  if (ncFeed && req.method === 'PUT') {
    const feedId = Number(ncFeed[1]);
    let count = 0;
    for (const item of NC_ITEMS) {
      if (item.feedId === feedId && item.unread) {
        item.unread = false;
        count++;
      }
    }
    log(req.method, pathname, query, '200 feed ' + feedId + ' all read (' + count + ')');
    return sendEmpty(res, 200);
  }

  log(req.method, pathname, query, '404 not found');
  return sendJson(res, 404, { error: 'not found: ' + route });
}

/* --------------------------------------------------------------- Fever ---- */

const FEVER_USER = 'fever@mock.test';
const FEVER_PASS = 'feverpass';

/**
 * The one thing worth checking carefully: Fever's `api_key` is
 * `md5(email:password)`. The client's own MD5 is compared against Node's, so a
 * mismatch shows up in the log rather than as a vague auth failure.
 */
const FEVER_KEY = crypto.createHash('md5')
  .update(FEVER_USER + ':' + FEVER_PASS).digest('hex');

const FEVER_FEEDS = [
  {
    id: 1, favicon_id: 0, title: 'Fever Tech',
    url: 'https://mock.test/fever-tech.xml',
    site_url: 'https://mock.test/fever-tech',
    is_spark: 0, last_updated_on_time: 1700000000
  },
  {
    id: 2, favicon_id: 0, title: 'Fever News',
    url: 'https://mock.test/fever-news.xml',
    site_url: 'https://mock.test/fever-news',
    is_spark: 0, last_updated_on_time: 1700000000
  }
];

const FEVER_GROUPS = [{ id: 1, title: 'Fever Folder' }];
const FEVER_FEEDS_GROUPS = [{ group_id: 1, feed_ids: '1' }];

const FEVER_ITEMS = [];
for (let i = 1; i <= 8; i++) {
  FEVER_ITEMS.push({
    id: 5000 + i,
    feed_id: i % 2 === 1 ? 1 : 2,
    title: 'Fever item #' + i,
    author: 'Fever Author',
    // A reachable image, so the cover-image actions have something to act on.
    html: '<p>Body of Fever item ' + i + '</p>'
      + '<img src="http://127.0.0.1:8899/img/' + i + '.png"/>',
    url: 'https://mock.test/fever-post/' + i,
    is_saved: i === 1 ? 1 : 0,
    is_read: 0,
    created_on_time: Math.floor(Date.UTC(2024, 4, i, 9, 0, 0) / 1000)
  });
}

/** Fever reports these as comma-separated strings, not arrays. */
function feverUnreadIds() {
  return FEVER_ITEMS.filter(i => i.is_read === 0).map(i => i.id).join(',');
}

function feverSavedIds() {
  return FEVER_ITEMS.filter(i => i.is_saved === 1).map(i => i.id).join(',');
}

async function handleFever(req, res, pathname, query) {
  const raw = await readBody(req);
  const form = new URLSearchParams(raw);
  const key = form.get('api_key') || '';
  const auth = key === FEVER_KEY ? 1 : 0;
  log(req.method, pathname, query,
    'api_key ' + (auth === 1 ? 'matches md5(email:password)' : 'MISMATCH -> ' + key));

  const response = { api_version: 3, auth: auth };
  if (auth !== 1) {
    return sendJson(res, 200, response);
  }
  response.last_refreshed_on_time = String(Math.floor(Date.now() / 1000));

  // Writes arrive as POST form fields, never as query arguments.
  const mark = form.get('mark');
  if (mark === 'item') {
    const id = Number(form.get('id'));
    const as = form.get('as');
    const item = FEVER_ITEMS.find(i => i.id === id);
    if (item) {
      if (as === 'read') item.is_read = 1;
      if (as === 'unread') item.is_read = 0;
      if (as === 'saved') item.is_saved = 1;
      if (as === 'unsaved') item.is_saved = 0;
    }
    log(req.method, pathname, query, 'mark item ' + id + ' as ' + as
      + ' -> unread=[' + feverUnreadIds() + '] saved=[' + feverSavedIds() + ']');
    response.unread_item_ids = feverUnreadIds();
    response.saved_item_ids = feverSavedIds();
    return sendJson(res, 200, response);
  }

  if (mark === 'feed') {
    const feedId = Number(form.get('id'));
    const before = Number(form.get('before') || '0');
    let count = 0;
    for (const item of FEVER_ITEMS) {
      if (item.feed_id === feedId && item.is_read === 0 && item.created_on_time <= before) {
        item.is_read = 1;
        count++;
      }
    }
    log(req.method, pathname, query, 'mark feed ' + feedId + ' read before ' + before
      + ' -> ' + count + ' item(s)');
    response.unread_item_ids = feverUnreadIds();
    return sendJson(res, 200, response);
  }

  // Reads arrive as query arguments.
  if (query.feeds !== undefined) {
    response.feeds = FEVER_FEEDS;
    response.feeds_groups = FEVER_FEEDS_GROUPS;
    log(req.method, pathname, query, '200 ' + FEVER_FEEDS.length + ' feeds');
  }
  if (query.groups !== undefined) {
    response.groups = FEVER_GROUPS;
    response.feeds_groups = FEVER_FEEDS_GROUPS;
    log(req.method, pathname, query, '200 ' + FEVER_GROUPS.length + ' groups');
  }
  if (query.items !== undefined) {
    const sinceId = Number(query.since_id || '0');
    const list = FEVER_ITEMS.filter(i => i.id > sinceId)
      .sort((a, b) => a.id - b.id).slice(0, 50);
    response.items = list;
    response.total_items = FEVER_ITEMS.length;
    log(req.method, pathname, query, '200 ' + list.length + ' items since_id=' + sinceId);
  }
  if (query.unread_item_ids !== undefined) {
    response.unread_item_ids = feverUnreadIds();
    log(req.method, pathname, query, '200 unread=[' + response.unread_item_ids + ']');
  }
  if (query.saved_item_ids !== undefined) {
    response.saved_item_ids = feverSavedIds();
    log(req.method, pathname, query, '200 saved=[' + response.saved_item_ids + ']');
  }

  return sendJson(res, 200, response);
}

const server = http.createServer(async (req, res) => {
  const parsed = url.parse(req.url, true);
  const pathname = parsed.pathname;
  const query = parsed.query;

  // Optional latency (see DELAY_MS) so in-flight UI states can be inspected.
  if (DELAY_MS > 0) {
    await new Promise(resolve => setTimeout(resolve, DELAY_MS));
  }

  // Full-content fixtures, served before any auth so the app can fetch them.
  if (pathname === '/full.xml') {
    log(req.method, pathname, query, '200 local feed');
    res.writeHead(200, { 'Content-Type': 'application/rss+xml; charset=utf-8' });
    return res.end(localFeedXml());
  }

  // Notification fixtures. `NOTIFY_COUNT` decides how many items exist, so the
  // mock can be restarted with one more item to make "a genuinely new article
  // arrived" happen on the next fetch (rules -> notify -> system notification).
  if (pathname === '/notify.xml') {
    log(req.method, pathname, query, '200 notify feed, ' + notifyCount() + ' items');
    res.writeHead(200, { 'Content-Type': 'application/rss+xml; charset=utf-8' });
    return res.end(notifyFeedXml());
  }

  const articleMatch = pathname.match(/^\/article\/(\d+)$/);
  if (articleMatch) {
    log(req.method, pathname, query, '200 article page');
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    return res.end(articlePage(Number(articleMatch[1])));
  }

  // The picture the article page points at, for the reader's inline images.
  if (pathname === '/img/diagram.png') {
    log(req.method, pathname, query, '200 png ' + DIAGRAM_PNG.length + ' bytes');
    res.writeHead(200, { 'Content-Type': 'image/png', 'Content-Length': DIAGRAM_PNG.length });
    return res.end(DIAGRAM_PNG);
  }

  // Feedbin: hosted JSON REST, HTTP Basic.
  if (pathname.startsWith('/v2/')) {
    return handleFeedbin(req, res, pathname, query);
  }

  // Nextcloud News: instance-relative JSON REST, HTTP Basic.
  if (pathname.indexOf('/apps/news/api/') >= 0) {
    return handleNextcloud(req, res, pathname, query);
  }

  // Fever: JSON over POST, `api_key` in the body, read args in the query.
  if (pathname.indexOf('/fever/') >= 0 || pathname.endsWith('fever.php')) {
    return handleFever(req, res, pathname, query);
  }

  // Images referenced by the fixtures, for the cover-image actions.
  if (/^\/img\/\d+\.png$/.test(pathname)) {
    log(req.method, pathname, query, '200 image');
    res.writeHead(200, { 'Content-Type': 'image/png' });
    return res.end(TINY_PNG);
  }

  // Google Reader API surface.
  if (pathname.startsWith('/reader/api/0/') || pathname === '/accounts/ClientLogin') {
    return handleGReader(req, res, pathname, query);
  }

  // /v1/me is the auth probe; it must still reject bad credentials.
  if (pathname === '/v1/me') {
    if (!authorized(req)) {
      log(req.method, pathname, query, '401 unauthorized');
      return sendJson(res, 401, { error_message: 'Invalid credentials' });
    }
    log(req.method, pathname, query, '200 ok');
    return sendJson(res, 200, { id: 1, username: 'tester', is_admin: false });
  }

  if (!authorized(req)) {
    log(req.method, pathname, query, '401 unauthorized');
    return sendJson(res, 401, { error_message: 'Invalid credentials' });
  }

  if (pathname === '/v1/categories' && req.method === 'GET') {
    log(req.method, pathname, query, CATEGORIES.length + ' categories');
    return sendJson(res, 200, CATEGORIES);
  }

  if (pathname === '/v1/feeds' && req.method === 'GET') {
    log(req.method, pathname, query, FEEDS.length + ' feeds');
    return sendJson(res, 200, FEEDS);
  }

  if (pathname === '/v1/entries' && req.method === 'GET') {
    let rows = ENTRIES.map(projectEntry);

    if (query.status) {
      rows = rows.filter(e => e.status === query.status);
    }
    if (query.starred === 'true') {
      rows = rows.filter(e => e.starred === true);
    }
    if (query.feed_id) {
      rows = rows.filter(e => String(e.feed.id) === String(query.feed_id));
    }
    if (query.category_id) {
      rows = rows.filter(e => String(e.feed.category.id) === String(query.category_id));
    }

    // id cursor used by the incremental walk
    if (query.after_entry_id) {
      rows = rows.filter(e => e.id > Number(query.after_entry_id));
    }
    if (query.before_entry_id) {
      rows = rows.filter(e => e.id < Number(query.before_entry_id));
    }

    const order = query.order || 'published_at';
    const direction = query.direction === 'asc' ? 1 : -1;
    rows.sort((a, b) => {
      if (order === 'id') return (a.id - b.id) * direction;
      return (Date.parse(a.published_at) - Date.parse(b.published_at)) * direction;
    });

    const total = rows.length;
    const offset = parseInt(query.offset || '0', 10);
    const limit = parseInt(query.limit || '100', 10);
    rows = rows.slice(offset, offset + limit);

    log(req.method, pathname, query,
      rows.length + ' of ' + total + ' entries returned');
    return sendJson(res, 200, { total, entries: rows });
  }

  if (pathname === '/v1/entries' && req.method === 'PUT') {
    const raw = await readBody(req);
    let payload;
    try {
      payload = JSON.parse(raw);
    } catch (err) {
      log(req.method, pathname, query, '400 malformed body');
      return sendJson(res, 400, { error_message: 'Bad JSON' });
    }
    const ids = payload.entry_ids || [];
    for (const id of ids) {
      state.statuses.set(Number(id), payload.status);
    }
    log(req.method, pathname, query,
      ids.length + ' entries -> ' + payload.status);
    return sendEmpty(res, 204);
  }

  const bookmarkMatch = pathname.match(/^\/v1\/entries\/(\d+)\/bookmark$/);
  if (bookmarkMatch && req.method === 'PUT') {
    const id = Number(bookmarkMatch[1]);
    const next = !state.starred.get(id);
    state.starred.set(id, next);
    log(req.method, pathname, query, 'entry ' + id + ' starred=' + next);
    return sendEmpty(res, 204);
  }

  const markFeedMatch = pathname.match(/^\/v1\/feeds\/(\d+)\/mark-all-as-read$/);
  if (markFeedMatch && req.method === 'PUT') {
    const feedId = Number(markFeedMatch[1]);
    let count = 0;
    for (const entry of ENTRIES) {
      if (entry.feed.id === feedId && state.statuses.get(entry.id) === 'unread') {
        state.statuses.set(entry.id, 'read');
        count++;
      }
    }
    log(req.method, pathname, query, count + ' entries marked read');
    return sendEmpty(res, 204);
  }

  log(req.method, pathname, query, '404 not found');
  return sendJson(res, 404, { error_message: 'Not found: ' + pathname });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log('Mock reader server listening on http://0.0.0.0:' + PORT);
  console.log('');
  console.log('  --- Miniflux API (/v1/*) ---');
  console.log('    token      : ' + TOKEN);
  console.log('    basic auth : tester:secret');
  console.log('    fixtures   : ' + FEEDS.length + ' feeds, ' +
    CATEGORIES.length + ' categories, ' + ENTRIES.length + ' entries');
  console.log('');
  console.log('  --- Google Reader API (/reader/api/0/*) ---');
  console.log('    login      : reader@mock.test / gr-secret');
  console.log('    fixtures   : ' + GR_SUBSCRIPTIONS.length + ' subscriptions, ' +
    GR_ENTRIES.length + ' entries');
  console.log('');
});
