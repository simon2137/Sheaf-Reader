/**
 * Read-only Miniflux live probe.
 *
 * Exercises the same request shapes `MinifluxService.ets` uses (same endpoints,
 * same `X-Auth-Token` header, same JSON parsing expectations) against a real
 * server, so credentials and pagination behaviour can be checked before the app
 * is pointed at it. **This script only issues GET requests** — no read/unread
 * status changes, no bookmark toggles, nothing that mutates the account.
 *
 *   $env:MINIFLUX_URL = 'https://your.miniflux.example/v1/'   # no default: this
 *   $env:MINIFLUX_TOKEN = '...'                               # is never written to disk
 *   node verify/miniflux-live.js          # summary probes (limit=1)
 *   node verify/miniflux-live.js sweep    # additionally walk the unread/starred
 *                                         # id sets exactly like a sync does
 *   node verify/miniflux-live.js state    # account/feed totals and the newest 20
 */
const https = require('https');
const { URL } = require('url');

// Both the endpoint and the token come from the environment: a real instance
// address and a real token must never end up in the repository.
const BASE = (process.env.MINIFLUX_URL || '').replace(/\/?$/, '/');
const TOKEN = process.env.MINIFLUX_TOKEN || '';
const MODE = process.argv[2] || 'summary';
const PAGE = 1000;   // MinifluxService.SYNC_PAGE

if (BASE.length === 0) {
  console.error('MINIFLUX_URL is not set, e.g. https://your.miniflux.example/v1/');
  process.exit(2);
}
if (!TOKEN) {
  console.error('MINIFLUX_TOKEN is not set.');
  process.exit(2);
}

function get(path) {
  return new Promise((resolve) => {
    const url = new URL(BASE + path);
    const started = Date.now();
    const request = https.get({
      hostname: url.hostname,
      port: url.port || 443,
      path: url.pathname + url.search,
      headers: { 'X-Auth-Token': TOKEN, 'Accept': 'application/json' }
    }, (response) => {
      let body = '';
      response.on('data', (chunk) => { body += chunk; });
      response.on('end', () => {
        resolve({
          status: response.statusCode,
          ms: Date.now() - started,
          bytes: Buffer.byteLength(body),
          body
        });
      });
    });
    request.on('error', (err) => {
      resolve({ status: 0, ms: Date.now() - started, bytes: 0, body: String(err.message) });
    });
    request.setTimeout(30000, () => request.destroy(new Error('timeout')));
  });
}

function parse(result) {
  try {
    return JSON.parse(result.body);
  } catch (e) {
    return null;
  }
}

function line(label, result, extra) {
  console.log(
    label.padEnd(34) + String(result.status).padStart(4) + '  ' +
    String(result.ms).padStart(6) + 'ms  ' + String(result.bytes).padStart(8) + 'B  ' +
    (extra === undefined ? '' : extra));
}

(async () => {
  console.log('base: ' + BASE);
  console.log('mode: ' + MODE + '  (GET only — this script never writes)\n');
  console.log('call'.padEnd(34) + 'code' + '     time' + '         size');

  const me = await get('me');
  const meJson = parse(me);
  line('GET /v1/me', me,
    meJson ? 'user=' + meJson.username + ' id=' + meJson.id + ' admin=' + meJson.is_admin : me.body.slice(0, 60));

  const feeds = await get('feeds');
  const feedsJson = parse(feeds);
  line('GET /v1/feeds', feeds, Array.isArray(feedsJson) ? feedsJson.length + ' feeds' : feeds.body.slice(0, 60));

  const categories = await get('categories');
  const catJson = parse(categories);
  line('GET /v1/categories', categories,
    Array.isArray(catJson) ? catJson.map(c => c.title).join(', ') || '(none)' : categories.body.slice(0, 60));

  // `total` is what the app's state sync walks; limit=1 keeps the load minimal.
  const unread = await get('entries?status=unread&limit=1&offset=0');
  const unreadJson = parse(unread);
  line('GET entries?status=unread (1)', unread,
    unreadJson ? 'total unread=' + unreadJson.total : unread.body.slice(0, 60));

  const starred = await get('entries?starred=true&limit=1&offset=0');
  const starredJson = parse(starred);
  line('GET entries?starred=true (1)', starred,
    starredJson ? 'total starred=' + starredJson.total : starred.body.slice(0, 60));

  // The new-item cursor the app walks on every sync.
  const newest = await get('entries?order=id&direction=desc&limit=3');
  const newestJson = parse(newest);
  line('GET entries?order=id desc (3)', newest,
    newestJson && newestJson.entries && newestJson.entries.length
      ? 'newest id=' + newestJson.entries[0].id + ' (' + newestJson.entries[0].title.slice(0, 36) + ')'
      : newest.body.slice(0, 60));

  if (Array.isArray(feedsJson)) {
    console.log('\nfeeds:');
    for (const feed of feedsJson) {
      console.log('  id=' + String(feed.id).padEnd(6) + ' cat=' + String(feed.category ? feed.category.title : '-').padEnd(14) +
        ' unread=' + String(feed.unread_count === undefined ? '?' : feed.unread_count).padEnd(6) +
        feed.title);
    }
  }

  if (MODE === 'state') {
    /*
     * The account's ground truth, shaped like what the app stores after a sync:
     * how many entries exist at all, how many are unread/starred, and the exact
     * pages the incremental walk returns. Diffing this against the app's own
     * list is what turns "the sync looked fine" into a checkable claim.
     */
    const total = await get('entries?limit=1');
    const totalJson = parse(total);
    line('GET entries (all)', total, totalJson ? 'total=' + totalJson.total : '');

    const oldest = await get('entries?order=id&direction=asc&limit=3');
    const oldestJson = parse(oldest);
    line('GET entries?order=id asc (3)', oldest,
      oldestJson && oldestJson.entries && oldestJson.entries.length
        ? 'oldest id=' + oldestJson.entries[0].id : '');

    // Page 1 of the app's walk: entries with id > 0, newest first.
    const page1 = await get('entries?order=id&direction=desc&after_entry_id=0&limit=125');
    const page1Json = parse(page1);
    line('walk page 1 (after=0, limit=125)', page1,
      page1Json && page1Json.entries
        ? page1Json.entries.length + ' entries, ids ' +
          page1Json.entries[page1Json.entries.length - 1].id + '..' + page1Json.entries[0].id : '');

    if (page1Json && page1Json.entries && page1Json.entries.length >= 125) {
      // Page 2 mirrors the app: same `after`, with `before` at the last id seen.
      const cursor = page1Json.entries[page1Json.entries.length - 1].id;
      const page2 = await get('entries?order=id&direction=desc&after_entry_id=0&before_entry_id=' +
        cursor + '&limit=125');
      const page2Json = parse(page2);
      line('walk page 2 (before=' + cursor + ')', page2,
        page2Json && page2Json.entries ? page2Json.entries.length + ' entries' : '');
    }

    // Per-feed totals, so the app's per-feed counts can be compared one by one.
    if (Array.isArray(feedsJson)) {
      console.log('\nper-feed entry totals:');
      for (const feed of feedsJson) {
        const perFeed = await get('entries?feed_id=' + feed.id + '&limit=1');
        const perFeedJson = parse(perFeed);
        const perFeedUnread = await get('entries?feed_id=' + feed.id + '&status=unread&limit=1');
        const perFeedUnreadJson = parse(perFeedUnread);
        line('  entries?feed_id=' + feed.id, perFeed,
          'total=' + (perFeedJson ? perFeedJson.total : '?') +
          ' unread=' + (perFeedUnreadJson ? perFeedUnreadJson.total : '?') +
          '  ' + feed.title);
      }
    }

    const newest = await get('entries?order=id&direction=desc&limit=20');
    const newestJson = parse(newest);
    if (newestJson && newestJson.entries) {
      console.log('\nnewest 20 entries on the server:');
      for (const e of newestJson.entries) {
        console.log('  id=' + String(e.id).padEnd(9) + ' feed=' + String(e.feed_id).padEnd(4) +
          ' ' + String(e.status).padEnd(6) + ' star=' + String(e.starred).padEnd(6) +
          ' ' + (e.published_at || e.created_at || '').slice(0, 19) +
          '  ' + (e.title || '').slice(0, 40));
      }
    }
  } else if (MODE === 'sizing') {
    // One page of each shape the app actually requests, to size the load on a
    // large account without walking the whole set.
    const unreadPage = await get('entries?status=unread&limit=' + PAGE + '&offset=0');
    const unreadPageJson = parse(unreadPage);
    line('GET entries?status=unread (1000)', unreadPage,
      unreadPageJson && unreadPageJson.entries ? unreadPageJson.entries.length + ' entries, total=' + unreadPageJson.total : '');
    const walkPage = await get('entries?order=id&direction=desc&after_entry_id=0&limit=125');
    const walkPageJson = parse(walkPage);
    line('GET entries?order=id&after=0 (125)', walkPage,
      walkPageJson && walkPageJson.entries ? walkPageJson.entries.length + ' entries' : '');
  } else if (MODE === 'sweep') {
    for (const params of ['status=unread', 'starred=true']) {
      let offset = 0;
      let collected = 0;
      let requests = 0;
      const started = Date.now();
      for (;;) {
        const page = await get('entries?' + params + '&limit=' + PAGE + '&offset=' + offset);
        const json = parse(page);
        if (page.status !== 200 || !json || !json.entries) {
          console.log('\nsweep ' + params + ': aborted at offset ' + offset + ' (status ' + page.status + ')');
          break;
        }
        requests++;
        collected += json.entries.length;
        if (json.entries.length < PAGE) {
          console.log('\nsweep ' + params + ': ' + collected + ' ids in ' + requests +
            ' requests, ' + (Date.now() - started) + 'ms');
          break;
        }
        offset += PAGE;
      }
    }
  } else {
    console.log('\n(sweep skipped — run `node verify/miniflux-live.js sweep` to walk the id sets like a sync does)');
  }
})();
