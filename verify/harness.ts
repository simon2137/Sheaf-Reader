/**
 * Behavioural harness for the shipped FeedParser / UrlUtils sources.
 *
 * The .ets sources are copied verbatim into verify/src and transpiled by
 * DevEco's bundled tsc, so these assertions exercise the real ported code
 * rather than a re-implementation.
 */
import { FeedParser } from './src/utils/FeedParser';
import { UrlUtils } from './src/utils/UrlUtils';
import { FeedFetcher } from './src/utils/FeedFetcherStub';
import { Feed, FeedGroup, Article, SourceRule, RuleActions, AppLog, AppLogType, RefreshOutcome, FetchFailure, SearchEngine, LoadedPage, AppSettings, DarkModeSetting } from './src/model/Models';
import { FilterType, FeedFilter, FilterableItem, RuleSearchScope } from './src/model/Filter';
import { RuleEngine } from './src/services/RuleEngine';
import { BackupService, BackupFile } from './src/services/BackupServiceStub';
import { HttpClient } from './src/data/HttpClientStub';
import { ContentExtractor } from './src/utils/ContentExtractor';
import { moveItem, idsOf, Identified } from './src/utils/ListOrder';
import { ImageActions } from './src/utils/ImageActionsStub';
import { I18n } from './src/utils/I18n';
import { SearchEngines } from './src/utils/SearchEngines';
import { StorageSize } from './src/utils/StorageSize';
import { TimeBounds } from './src/utils/TimeBounds';
import { ScopeFilter } from './src/utils/ScopeFilter';
import { SourceFilter } from './src/utils/SourceFilter';
import { SidebarState, SIDEBAR_BREAKPOINT, SIDEBAR_WIDTH } from './src/utils/SidebarState';
import { FetchSchedule } from './src/utils/FetchSchedule';
import { ReaderBody, ReaderBlock } from './src/utils/ReaderBody';
import { TouchTarget } from './src/utils/TouchTarget';

declare const require: (name: string) => any;
declare const process: { exit(code: number): void };
const fs = require('fs');

let passed = 0;
let failed = 0;

function check(name: string, condition: boolean, detail?: string): void {
  if (condition) {
    passed++;
    console.log('  PASS  ' + name);
  } else {
    failed++;
    console.log('  FAIL  ' + name + (detail ? '  -> ' + detail : ''));
  }
}

function section(title: string): void {
  console.log('\n== ' + title + ' ==');
}

// ---------------------------------------------------------------- samples

const RSS_20 = `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Example Tech Blog</title>
    <link>https://blog.example.com</link>
    <description>Thoughts on software</description>
    <item>
      <title>Shipping ArkTS &amp; You</title>
      <link>https://blog.example.com/arkts</link>
      <guid isPermaLink="false">post-001</guid>
      <pubDate>Mon, 15 Jan 2024 09:30:00 GMT</pubDate>
      <dc:creator>Ada Lovelace</dc:creator>
      <description><![CDATA[<p>ArkTS is a <b>typed</b> dialect.</p>]]></description>
      <enclosure url="https://blog.example.com/cover.png" type="image/png" length="1234"/>
    </item>
    <item>
      <title>Second Post</title>
      <link>https://blog.example.com/two</link>
      <pubDate>Tue, 16 Jan 2024 11:00:00 GMT</pubDate>
      <description>Plain &lt;escaped&gt; description</description>
    </item>
  </channel>
</rss>`;

const ATOM_10 = `<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Atom Example</title>
  <subtitle>A test atom feed</subtitle>
  <link href="https://atom.example.org/" rel="alternate"/>
  <entry>
    <title>Hello Atom</title>
    <id>urn:uuid:1225c695-cfb8-4ebb-aaaa-80da344efa6a</id>
    <link href="https://atom.example.org/hello"/>
    <updated>2024-03-02T12:00:00Z</updated>
    <author><name>Grace Hopper</name></author>
    <content type="html">&lt;p&gt;Atom content body&lt;/p&gt;</content>
  </entry>
  <entry>
    <title>No Id Entry</title>
    <link href="https://atom.example.org/noid"/>
    <updated>2024-03-03T08:15:00Z</published>
    <summary>Summary only</summary>
  </entry>
</feed>`;

const OPML = `<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
  <head><title>Subscriptions</title></head>
  <body>
    <outline text="News" title="News">
      <outline type="rss" text="BBC" title="BBC" xmlUrl="https://feeds.bbci.co.uk/news/rss.xml" htmlUrl="https://bbc.co.uk"/>
      <outline type="rss" text="Reuters" xmlUrl="https://reuters.com/rss"/>
    </outline>
    <outline type="rss" text="Solo Blog" xmlUrl="https://solo.example.com/feed.xml"/>
  </body>
</opml>`;

// ------------------------------------------------------------------ tests

section('RSS 2.0 parsing');
const rss = FeedParser.parse(RSS_20, 'https://blog.example.com/rss');
check('feed parsed', rss !== null);
if (rss) {
  check('channel title decoded', rss.feed.title === 'Example Tech Blog', rss.feed.title);
  check('channel link', rss.feed.link === 'https://blog.example.com', rss.feed.link);
  check('article count is 2', rss.articles.length === 2, String(rss.articles.length));

  const first = rss.articles[0];
  check('entity-decoded title', first.title === 'Shipping ArkTS & You', first.title);
  check('guid from <guid>', first.guid === 'post-001', first.guid);
  check('dc:creator author', first.author === 'Ada Lovelace', first.author);
  check('CDATA content unwrapped', first.content.indexOf('ArkTS is a') >= 0, first.content);
  check('snippet has no markup', first.snippet.indexOf('<') < 0, first.snippet);
  check('enclosure image captured',
    first.imageUrl === 'https://blog.example.com/cover.png', first.imageUrl);

  const expected = Date.UTC(2024, 0, 15, 9, 30, 0);
  check('RFC-822 pubDate parsed', first.published === expected,
    new Date(first.published).toISOString());

  const second = rss.articles[1];
  check('guid falls back to link', second.guid === 'https://blog.example.com/two', second.guid);
  // Per the RSS spec an escaped "<x>" inside <description> denotes markup, so
  // it is stripped rather than shown literally. Authors who want to display
  // angle brackets must double-escape them.
  check('entity-escaped markup treated as markup, not literal text',
    second.snippet === 'Plain description', second.snippet);
  check('distinct ids', first.guid !== second.guid);
}

section('Atom 1.0 parsing');
const atom = FeedParser.parse(ATOM_10, 'https://atom.example.org/feed');
check('atom feed parsed', atom !== null);
if (atom) {
  check('atom title', atom.feed.title === 'Atom Example', atom.feed.title);
  check('atom subtitle as description',
    atom.feed.description === 'A test atom feed', atom.feed.description);
  check('atom feed link href',
    atom.feed.link === 'https://atom.example.org/', atom.feed.link);
  check('entry count is 2', atom.articles.length === 2, String(atom.articles.length));

  const e0 = atom.articles[0];
  check('entry title', e0.title === 'Hello Atom', e0.title);
  check('entry link href', e0.link === 'https://atom.example.org/hello', e0.link);
  check('entry id as guid',
    e0.guid === 'urn:uuid:1225c695-cfb8-4ebb-aaaa-80da344efa6a', e0.guid);
  check('atom author name extracted', e0.author === 'Grace Hopper', e0.author);
  check('atom ISO date parsed', e0.published === Date.UTC(2024, 2, 2, 12, 0, 0),
    new Date(e0.published).toISOString());

  const e1 = atom.articles[1];
  check('entry without id uses link',
    e1.guid === 'https://atom.example.org/noid', e1.guid);
  check('summary used as body', e1.snippet.indexOf('Summary only') >= 0, e1.snippet);
  check('entry without id has non-empty id', e1.guid.length > 0);
}

section('Malformed / hostile input');
check('empty string rejected', FeedParser.parse('', 'https://x.test') === null);
check('plain HTML rejected', FeedParser.parse('<html><body>hi</body></html>', 'https://x.test') === null);
check('truncated XML does not throw',
  FeedParser.parse('<rss><channel><title>X', 'https://x.test') === null);
const noItemFeed = FeedParser.parse(
  '<rss><channel><title>Empty</title><link>https://e.test</link></channel></rss>', 'https://e.test');
check('feed with zero items is valid', noItemFeed !== null && noItemFeed.articles.length === 0);

section('HTML stripping');
check('script removed',
  FeedParser.stripHtml('<p>a</p><script>evil()</script>').indexOf('evil') < 0);
check('style removed',
  FeedParser.stripHtml('<style>.x{}</style><p>b</p>').indexOf('.x') < 0);
check('tags removed', FeedParser.stripHtml('<h1>Title</h1>').trim() === 'Title',
  FeedParser.stripHtml('<h1>Title</h1>'));
check('nbsp decoded', FeedParser.stripHtml('a&nbsp;b').indexOf('\u00a0') < 0);
check('empty input safe', FeedParser.stripHtml('') === '');

section('OPML round-trip');
const parsedOpml = FeedParser.parseOpml(OPML);
check('three outlines found', parsedOpml.entries.length === 3,
  String(parsedOpml.entries.length));
check('grouped entry keeps group name',
  parsedOpml.entries[0].groupName === 'News', parsedOpml.entries[0].groupName);
check('grouped url', parsedOpml.entries[0].url === 'https://feeds.bbci.co.uk/news/rss.xml',
  parsedOpml.entries[0].url);
check('title falls back to text attr',
  parsedOpml.entries[1].title === 'Reuters', parsedOpml.entries[1].title);
check('ungrouped entry has empty group',
  parsedOpml.entries[2].groupName === '', '[' + parsedOpml.entries[2].groupName + ']');
check('ungrouped url', parsedOpml.entries[2].url === 'https://solo.example.com/feed.xml',
  parsedOpml.entries[2].url);

const feeds: Feed[] = [];
const f1 = new Feed('https://feeds.bbci.co.uk/news/rss.xml', 'BBC & Co');
f1.id = 1; f1.groupId = 10; f1.link = 'https://bbc.co.uk';
feeds.push(f1);
const f2 = new Feed('https://solo.example.com/feed.xml', 'Solo "Blog"');
f2.id = 2; f2.groupId = -1; f2.link = 'https://solo.example.com';
feeds.push(f2);

const groups: FeedGroup[] = [];
const g = new FeedGroup();
g.id = 10; g.name = 'News & Views';
groups.push(g);

const generated = FeedParser.generateOpml(feeds, groups);
check('opml declares version 2.0', generated.indexOf('<opml version="2.0">') >= 0);
check('group outline present', generated.indexOf('News &amp; Views') >= 0);
check('xml-special chars escaped', generated.indexOf('BBC &amp; Co') >= 0);
check('quotes escaped', generated.indexOf('Solo &quot;Blog&quot;') >= 0);

const reparsed = FeedParser.parseOpml(generated);
check('generated opml re-parses to 2 feeds', reparsed.entries.length === 2,
  String(reparsed.entries.length));
check('escaped group name survives round-trip',
  reparsed.entries[0].groupName === 'News & Views', reparsed.entries[0].groupName);
check('escaped title survives round-trip',
  reparsed.entries[0].title === 'BBC & Co', reparsed.entries[0].title);
check('ungrouped stays ungrouped after round-trip',
  reparsed.entries[1].groupName === '');

section('OPML nesting depth');
const NESTED_OPML = `<opml version="2.0"><body>
  <outline text="Tech">
    <outline type="rss" text="Outer Feed" xmlUrl="https://a.test/1"/>
    <outline text="Languages">
      <outline type="rss" text="Inner Feed" xmlUrl="https://a.test/2"/>
    </outline>
    <outline type="rss" text="Back To Tech" xmlUrl="https://a.test/3"/>
  </outline>
  <outline type="rss" text="Top Level" xmlUrl="https://a.test/4"/>
  <outline text="Empty Group"/>
  <outline type="rss" text="After Empty" xmlUrl="https://a.test/5"/>
</body></opml>`;

const nested = FeedParser.parseOpml(NESTED_OPML);
check('five feeds discovered', nested.entries.length === 5, String(nested.entries.length));
if (nested.entries.length === 5) {
  check('outer feed in "Tech"', nested.entries[0].groupName === 'Tech',
    '[' + nested.entries[0].groupName + ']');
  check('inner feed in "Languages"', nested.entries[1].groupName === 'Languages',
    '[' + nested.entries[1].groupName + ']');
  check('feed after nested group returns to "Tech"', nested.entries[2].groupName === 'Tech',
    '[' + nested.entries[2].groupName + ']');
  check('top-level feed after group closes is ungrouped',
    nested.entries[3].groupName === '', '[' + nested.entries[3].groupName + ']');
  check('self-closing empty group does not capture later feeds',
    nested.entries[4].groupName === '', '[' + nested.entries[4].groupName + ']');
}

section('Split / repeated CDATA sections');
// 阮一峰's Atom feed puts several sibling CDATA blocks inside one <content>.
// A "<tag><![CDATA[x]]></tag>" pattern fails to match and leaks raw markup.
const MULTI_CDATA = `<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Multi CDATA</title>
  <entry>
    <title>Split body</title>
    <id>split-1</id>
    <link href="https://multi.test/1"/>
    <updated>2024-05-01T00:00:00Z</updated>
    <content type="html">
        <![CDATA[<p>First block</p>
]]>
        <![CDATA[<p>Second block</p>
]]>
        <![CDATA[<p>Third block</p>]]>
    </content>
  </entry>
</feed>`;

const multi = FeedParser.parse(MULTI_CDATA, 'https://multi.test/feed');
check('multi-CDATA feed parsed', multi !== null);
if (multi && multi.articles.length === 1) {
  const body = multi.articles[0].content;
  check('all three blocks kept',
    body.indexOf('First block') >= 0 && body.indexOf('Second block') >= 0
    && body.indexOf('Third block') >= 0, body.substring(0, 80));
  check('no CDATA opener leaks', body.indexOf('<![CDATA[') < 0);
  check('no CDATA terminator leaks', body.indexOf(']]>') < 0,
    'found ]]> in: ' + body.substring(Math.max(0, body.indexOf(']]>') - 30), body.indexOf(']]>') + 10));
  check('real markup preserved for downstream rendering',
    body.indexOf('<p>') >= 0, body.substring(0, 60));
}

const rssMulti = FeedParser.parse(`<rss version="2.0"><channel><title>T</title>
<item><title>I</title><guid>g1</guid>
<description><![CDATA[<b>alpha</b>]]><![CDATA[ and <i>beta</i>]]></description>
</item></channel></rss>`, 'https://multi.test/rss');
check('rss multi-CDATA parsed', rssMulti !== null && rssMulti.articles.length === 1);
if (rssMulti && rssMulti.articles.length === 1) {
  check('both description blocks concatenated',
    rssMulti.articles[0].content.indexOf('alpha') >= 0
    && rssMulti.articles[0].content.indexOf('beta') >= 0,
    rssMulti.articles[0].content);
  check('rss snippet free of CDATA markers',
    rssMulti.articles[0].snippet.indexOf(']]>') < 0
    && rssMulti.articles[0].snippet.indexOf('CDATA') < 0,
    rssMulti.articles[0].snippet);
}

check('stray CDATA marker stripped from plain text',
  FeedParser.stripHtml('a ]]> b').indexOf(']]>') < 0,
  FeedParser.stripHtml('a ]]> b'));

section('Entity-escaped markup (sspai-style)');
// sspai ships "<description>&lt;p&gt;...&lt;a href=&quot;...&quot;&gt;" — the
// markup is escaped, so entities must be decoded BEFORE tags are stripped.
const ESCAPED_DESC = `<rss version="2.0"><channel><title>Esc</title>
<item><title>Escaped</title><guid>esc-1</guid>
<description>&lt;p&gt;Hello &lt;strong&gt;world&lt;/strong&gt;.&lt;/p&gt;&lt;p&gt;See &lt;a href=&#34;https://x.test/p/1&#34; target=&#34;_blank&#34;&gt;full text&lt;/a&gt;&lt;/p&gt;</description>
</item></channel></rss>`;

const esc = FeedParser.parse(ESCAPED_DESC, 'https://esc.test/feed');
check('escaped-description feed parsed', esc !== null && esc.articles.length === 1);
if (esc && esc.articles.length === 1) {
  const snip = esc.articles[0].snippet;
  check('no escaped markup survives in snippet', snip.indexOf('<') < 0, snip);
  check('no href attribute leaks into snippet', snip.indexOf('href') < 0, snip);
  check('no numeric entity leaks into snippet', snip.indexOf('&#') < 0, snip);
  check('visible text preserved', snip.indexOf('Hello') >= 0 && snip.indexOf('world') >= 0
    && snip.indexOf('full text') >= 0, snip);
}

check('stripHtml decodes then strips escaped tags',
  FeedParser.stripHtml('&lt;b&gt;bold&lt;/b&gt;').trim() === 'bold',
  FeedParser.stripHtml('&lt;b&gt;bold&lt;/b&gt;'));
check('stripHtml handles literal tags', FeedParser.stripHtml('<b>bold</b>').trim() === 'bold',
  FeedParser.stripHtml('<b>bold</b>'));
check('stripHtml unwraps double-escaped tags',
  FeedParser.stripHtml('&amp;lt;b&amp;gt;bold&amp;lt;/b&amp;gt;').trim() === 'bold',
  FeedParser.stripHtml('&amp;lt;b&amp;gt;bold&amp;lt;/b&amp;gt;'));
check('decodeEntities is exposed for the reader view',
  FeedParser.decodeEntities('&lt;i&gt;x&lt;/i&gt;') === '<i>x</i>',
  FeedParser.decodeEntities('&lt;i&gt;x&lt;/i&gt;'));

section('FeedFilter (composable bit flags)');
// The bit model is inverted: a clear bit REQUIRES that state. These assertions
// pin the three presets and the independent toggles.

function fi(o: Partial<FilterableItem>): FilterableItem {
  return Object.assign({
    title: '', snippet: '', creator: '',
    hasRead: false, starred: false, hidden: false
  }, o) as FilterableItem;
}

function ff(type: number, search: string = ''): FeedFilter {
  return new FeedFilter(type, search);
}

check('Default shows read articles',
  ff(FilterType.Default).testItem(fi({ hasRead: true })));
check('Default shows unstarred articles',
  ff(FilterType.Default).testItem(fi({ starred: false })));
check('Default hides hidden articles',
  !ff(FilterType.Default).testItem(fi({ hidden: true })));
check('Default | ShowHidden reveals hidden articles',
  ff(FilterType.Default | FilterType.ShowHidden).testItem(fi({ hidden: true })));

check('UnreadOnly keeps unread',
  ff(FilterType.UnreadOnly).testItem(fi({ hasRead: false })));
check('UnreadOnly drops read',
  !ff(FilterType.UnreadOnly).testItem(fi({ hasRead: true })));
check('StarredOnly keeps starred',
  ff(FilterType.StarredOnly).testItem(fi({ starred: true })));
check('StarredOnly drops unstarred',
  !ff(FilterType.StarredOnly).testItem(fi({ starred: false })));

// Which preset is active drives the checkmarks in the view menu, so the test
// has to be exactly "neither preset is narrowing the list" - it is not enough
// for one of the two preset bits to be set.
check('the default preset reports itself as "all articles"',
  ff(FilterType.Default).isAllPreset());
check('unread only is not "all articles"',
  !ff(FilterType.UnreadOnly).isAllPreset());
check('starred only is not "all articles"',
  !ff(FilterType.StarredOnly).isAllPreset());
check('both presets cleared is not "all articles"',
  !ff(0).isAllPreset());
check('toggles do not disturb the "all articles" test',
  ff(FilterType.Default | FilterType.ShowHidden | FilterType.FullSearch).isAllPreset());
check('a search toggle alone does not disturb the preset test',
  ff(FilterType.UnreadOnly | FilterType.CaseInsensitive).isAllPreset() === false);
check('the store default type is the "all articles" preset',
  ff(FilterType.Default | FilterType.CaseInsensitive).isAllPreset());

// The filter bits are persisted as a decimal string (the original's
// `SchemaTypes.filterType`), so whatever is written must read back identically -
// including the toggle bits a preset switch carries over.
const persistedType = ff(FilterType.UnreadOnly | FilterType.ShowHidden | FilterType.FullSearch).type;
check('a filter type survives the decimal round trip',
  parseInt(persistedType.toString(), 10) === persistedType, String(persistedType));
check('the persisted fallback equals the filter default',
  (FilterType.Default | FilterType.CaseInsensitive)
  === ff(FilterType.Default | FilterType.CaseInsensitive).type,
  String(ff(FilterType.Default | FilterType.CaseInsensitive).type));
check('a preset switch carries the toggle bits over',
  (FilterType.UnreadOnly
    | (ff(FilterType.Default | FilterType.ShowHidden).type & FilterType.Toggles))
  === (FilterType.UnreadOnly | FilterType.ShowHidden),
  String(ff(FilterType.Default | FilterType.ShowHidden).type & FilterType.Toggles));

// Presets compose with toggles, which is the whole point of the bit model.
check('UnreadOnly + ShowHidden still drops read',
  !ff(FilterType.UnreadOnly | FilterType.ShowHidden).testItem(fi({ hasRead: true })));
check('a scopeless filter (None) matches only starred AND unread',
  !ff(FilterType.None).testItem(fi({ starred: false, hasRead: false })));

// --- Search scope ----------------------------------------------------------
check('default search matches the title',
  ff(FilterType.Default, 'foo').testItem(fi({ title: 'a foo b' })));
check('default search ignores the snippet',
  !ff(FilterType.Default, 'foo').testItem(fi({ snippet: 'a foo b' })));
check('FullSearch also matches the snippet',
  ff(FilterType.Default | FilterType.FullSearch, 'foo').testItem(fi({ snippet: 'a foo b' })));
// The creator scope belongs to *rules* now. The list filter's own creator bit
// was removed on request, but the rule scope keeps the upstream value so rules
// already stored — by this port or by the original app — still match the author.
check('the rule creator scope matches the author',
  ff(FilterType.Default | RuleSearchScope.Creator, 'Ada').testItem(fi({ creator: 'Ada' })));
check('the rule creator scope ignores the title',
  !ff(FilterType.Default | RuleSearchScope.Creator, 'Ada').testItem(fi({ title: 'Ada' })));

// --- Case handling ---------------------------------------------------------
// The bit is positive: SET means case-INsensitive.
check('without CaseInsensitive the match is case sensitive',
  !ff(FilterType.Default, 'FOO').testItem(fi({ title: 'foo' })));
check('with CaseInsensitive the match ignores case',
  ff(FilterType.Default | FilterType.CaseInsensitive, 'FOO').testItem(fi({ title: 'foo' })));

// --- It is a regex, not a substring search ---------------------------------
check('search is a regular expression',
  ff(FilterType.Default, '^foo$').testItem(fi({ title: 'foo' })));
check('regex anchors are honoured',
  !ff(FilterType.Default, '^foo$').testItem(fi({ title: 'a foo b' })));
check('alternation works',
  ff(FilterType.Default, 'foo|bar').testItem(fi({ title: 'bar' })));
check('an invalid pattern matches nothing instead of throwing',
  !ff(FilterType.Default, '([bad').testItem(fi({ title: '([bad' })));

// --- SQL translation (search is intentionally absent) ----------------------
const sqlDefault = FeedFilter.toSql(ff(FilterType.Default));
// Default = ShowRead | ShowNotStarred, so read/starred are unconstrained, but
// ShowHidden is still clear and therefore hidden articles are excluded.
check('Default only excludes hidden articles',
  sqlDefault.sql === ' AND a.hidden = 0' && sqlDefault.args.length === 0,
  sqlDefault.sql);
const sqlUnread = FeedFilter.toSql(ff(FilterType.UnreadOnly));
check('UnreadOnly constrains read in SQL',
  sqlUnread.sql.indexOf('a.read = 0') >= 0, sqlUnread.sql);
const sqlStarred = FeedFilter.toSql(ff(FilterType.StarredOnly));
check('StarredOnly constrains starred in SQL',
  sqlStarred.sql.indexOf('a.starred = 1') >= 0, sqlStarred.sql);
const sqlHidden = FeedFilter.toSql(ff(FilterType.Default | FilterType.ShowHidden));
check('ShowHidden drops the hidden constraint',
  sqlHidden.sql.indexOf('hidden') < 0, sqlHidden.sql);
check('the search pattern is never pushed into SQL (REGEXP is unavailable)',
  FeedFilter.toSql(ff(FilterType.Default, 'foo.*bar')).sql.indexOf('LIKE') < 0
  && FeedFilter.toSql(ff(FilterType.Default, 'foo.*bar')).sql.indexOf('REGEXP') < 0);

check('testArticle projects an article onto the filter',
  FeedFilter.testArticle(ff(FilterType.UnreadOnly), 't', 's', 'c', false, false, false)
  && !FeedFilter.testArticle(ff(FilterType.UnreadOnly), 't', 's', 'c', true, false, false));

// A source can be marked "hide in all articles" (`sources.hidden`). That is a
// property of the source, not of the article, so it is only applied to the
// aggregate listing — selecting the source itself must still list its articles.
const sqlAggregate = FeedFilter.toSql(ff(FilterType.Default), true);
check('the aggregate listing excludes sources hidden from "all articles"',
  sqlAggregate.sql.indexOf('NOT IN (SELECT id FROM feeds WHERE hidden = 1)') >= 0,
  sqlAggregate.sql);
check('a source-scoped listing does not exclude those sources',
  FeedFilter.toSql(ff(FilterType.Default), false).sql.indexOf('NOT IN (SELECT') < 0);
check('showing hidden articles also brings back hidden sources',
  FeedFilter.toSql(ff(FilterType.Default | FilterType.ShowHidden), true)
    .sql.indexOf('NOT IN (SELECT') < 0);
check('the source-hidden clause adds no bound arguments',
  sqlAggregate.args.length === 0, String(sqlAggregate.args.length));

section('Rule engine');
// The rules subsystem is pure logic (no HarmonyOS kit imports), so the real
// RuleEngine / FeedFilter sources run here directly.

function makeItem(title: string, snippet: string, creator: string): Article {
  const a = new Article();
  a.title = title;
  a.snippet = snippet;
  a.author = creator;
  a.read = false;
  a.starred = false;
  a.hidden = false;
  a.notify = false;
  return a;
}

/**
 * The FilterType bits are INVERTED: a clear bit *requires* that state. So a
 * rule must set ShowRead / ShowNotStarred / ShowHidden, otherwise it would only
 * ever match unread, starred, visible articles. This is exactly the base the
 * original's `saveRule` builds.
 */
const RULE_BASE: number = FilterType.Default | FilterType.ShowHidden;

/** extraBits are OR'd onto the base, mirroring the original's rules UI. */
function makeRule(regex: string, extraBits: number, match: boolean,
  actions: string[]): SourceRule {
  const r = new SourceRule();
  r.regex = regex;
  r.filterType = RULE_BASE | extraBits;
  r.match = match;
  r.actions = actions;
  return r;
}

const readFlag = (a: Article): boolean => a.read;
const starFlag = (a: Article): boolean => a.starred;
const hideFlag = (a: Article): boolean => a.hidden;
const notifyFlag = (a: Article): boolean => a.notify;

// --- The inverted-bit trap ------------------------------------------------
// A rule built without the base bits can never match ordinary articles.
const bareRule = makeRule2('Weekly', FilterType.None, true, ['r-true']);
const ordinary = makeItem('Weekly digest', 'body', 'Ada');
RuleEngine.apply(bareRule, ordinary);
check('the bit model really is inverted: a scopeless rule misses',
  readFlag(ordinary) === false);

const starredItem = makeItem('Weekly digest', 'body', 'Ada');
starredItem.starred = true;
RuleEngine.apply(bareRule, starredItem);
check('...and the same rule fires once the article is starred',
  readFlag(starredItem) === true);

function makeRule2(regex: string, rawType: number, match: boolean,
  actions: string[]): SourceRule {
  const r = new SourceRule();
  r.regex = regex;
  r.filterType = rawType;
  r.match = match;
  r.actions = actions;
  return r;
}

// --- match / doesn't match -------------------------------------------------
const readAd = makeRule('\\[AD\\]', FilterType.None, true, ['r-true']);
const adItem = makeItem('[AD] Buy now', 'body', 'Ada');
RuleEngine.apply(readAd, adItem);
check('match=true fires on a matching title', readFlag(adItem) === true);

const cleanItem = makeItem('Weekly digest', 'body', 'Ada');
RuleEngine.apply(readAd, cleanItem);
check('match=true does not fire on a non-matching title',
  readFlag(cleanItem) === false);

const readNonAd = makeRule('\\[AD\\]', FilterType.None, false, ['r-true']);
const normal = makeItem('Weekly digest', 'body', 'Ada');
RuleEngine.apply(readNonAd, normal);
check("match=false ('doesn't match') fires on a non-matching title",
  readFlag(normal) === true);

const stillAd = makeItem('[AD] Buy now', 'body', 'Ada');
RuleEngine.apply(readNonAd, stillAd);
check("match=false does not fire on a matching title",
  readFlag(stillAd) === false);

// --- Scope: title vs title-or-content vs author ---------------------------
const titleOnly = makeRule('sponsored', FilterType.None, true, ['s-true']);
const titleHit = makeItem('Clean title', 'this is sponsored', 'Ada');
RuleEngine.apply(titleOnly, titleHit);
check('title scope ignores the snippet', starFlag(titleHit) === false);

const fullText = makeRule('sponsored', FilterType.FullSearch, true, ['s-true']);
const fullHit = makeItem('Clean title', 'this is sponsored', 'Ada');
RuleEngine.apply(fullText, fullHit);
check('full-search scope matches the snippet', starFlag(fullHit) === true);

const authorOnly = makeRule('^Grace$', RuleSearchScope.Creator, true, ['h-true']);
const graceItem = makeItem('Anything', 'anything', 'Grace');
RuleEngine.apply(authorOnly, graceItem);
check('creator scope matches the author', hideFlag(graceItem) === true);

const authorMiss = makeItem('Grace', 'Grace', 'Someone else');
RuleEngine.apply(authorOnly, authorMiss);
check('creator scope ignores title and snippet', hideFlag(authorMiss) === false);

// --- Case sensitivity ------------------------------------------------------
// Upstream's UI defaults to case-INsensitive (its `caseSensitive` starts false).
const sensitive = makeRule('AD', FilterType.None, true, ['r-true']);
const lower = makeItem('ad break', 'x', 'Ada');
RuleEngine.apply(sensitive, lower);
check('without CaseInsensitive, case matters', readFlag(lower) === false);

const insensitive = makeRule('AD', FilterType.CaseInsensitive, true, ['r-true']);
const lower2 = makeItem('ad break', 'x', 'Ada');
RuleEngine.apply(insensitive, lower2);
check('with CaseInsensitive, case is ignored', readFlag(lower2) === true);

// --- All four actions ------------------------------------------------------
const allActions = makeRule('x', FilterType.FullSearch, true,
  ['r-true', 's-true', 'h-true', 'n-true']);
const acted = makeItem('x', 'x', 'x');
RuleEngine.apply(allActions, acted);
check('all four actions applied',
  readFlag(acted) && starFlag(acted) && hideFlag(acted) && notifyFlag(acted));

// The UI exposes false variants too ("mark unread", "unstar", "unhide",
// "don't notify"), so an explicit false must clear the flag.
const unstar = makeRule('x', FilterType.FullSearch, true, ['s-false']);
const starredForUnstar = makeItem('x', 'x', 'x');
starredForUnstar.starred = true;
RuleEngine.apply(unstar, starredForUnstar);
check('action value false clears the flag', starFlag(starredForUnstar) === false);

check('RuleActions covers all eight action keys',
  RuleActions.fromKeys(['r-true', 'r-false', 's-true', 's-false',
    'h-true', 'h-false', 'n-true', 'n-false']).size === 4);

// A bare key with no "-value" suffix means "apply", matching upstream.
check('RuleActions.fromKeys treats a bare key as true',
  RuleActions.fromKeys(['r']).get('r') === true);
check('RuleActions.fromKeys parses an explicit value',
  RuleActions.fromKeys(['r-false']).get('r') === false);
const roundTrip = RuleActions.fromKeys(
  RuleActions.toKeys(RuleActions.fromKeys(['r-true', 's-false'])));
check('RuleActions key round-trip preserves values',
  roundTrip.get('r') === true && roundTrip.get('s') === false);

// --- Ordering: later rules override earlier ones --------------------------
const markRead = makeRule('x', FilterType.FullSearch, true, ['r-true']);
const markUnread = makeRule('x', FilterType.FullSearch, true, ['r-false']);
const ordered = makeItem('x', 'x', 'x');
RuleEngine.applyAll([markRead, markUnread], ordered);
check('rules apply in order, last one wins', readFlag(ordered) === false);

const reverse = makeItem('x', 'x', 'x');
RuleEngine.applyAll([markUnread, markRead], reverse);
check('reversing the order reverses the outcome', readFlag(reverse) === true);

// --- Robustness ------------------------------------------------------------
const badRegex = makeRule('([unclosed', FilterType.FullSearch, true, ['r-true']);
const badItem = makeItem('anything', 'anything', 'x');
let threw = false;
try {
  RuleEngine.apply(badRegex, badItem);
} catch (e) {
  threw = true;
}
check('invalid regex does not throw', !threw);
check('invalid regex does not match', readFlag(badItem) === false);

const emptyJsonItem = makeItem('x', 'x', 'x');
RuleEngine.applyForFeed('', emptyJsonItem);
check('applyForFeed with empty json is a no-op', readFlag(emptyJsonItem) === false);

const malformedItem = makeItem('x', 'x', 'x');
RuleEngine.applyForFeed('{not json', malformedItem);
check('applyForFeed tolerates malformed json', readFlag(malformedItem) === false);

// --- Persistence round-trip ------------------------------------------------
const stored = [makeRule('\\[AD\\]', FilterType.CaseInsensitive | FilterType.FullSearch,
  true, ['r-true', 'h-true'])];
const json = SourceRule.toJson(stored);
const restored = SourceRule.fromJson(json);
check('rule set survives a json round-trip', restored.length === 1);
check('round-trip keeps the pattern', restored[0].regex === '\\[AD\\]',
  restored[0].regex);
check('round-trip keeps the filter bits',
  restored[0].filterType
  === (RULE_BASE | FilterType.CaseInsensitive | FilterType.FullSearch),
  String(restored[0].filterType));
check('round-trip keeps the actions',
  restored[0].actions.length === 2 && restored[0].match === true);

const restoredItem = makeItem('[ad] sponsored', 'x', 'x');
RuleEngine.applyAll(restored, restoredItem);
check('restored rule still fires',
  readFlag(restoredItem) === true && hideFlag(restoredItem) === true);

check('validateRegex accepts a valid pattern',
  RuleEngine.validateRegex('\\[AD\\]', 'i'));
check('validateRegex rejects an invalid pattern',
  !RuleEngine.validateRegex('([unclosed', 'i'));

// The rules panel's "Test rules" action must report what a real fetch would do
// without changing anything, so `matches` is pinned against `apply`.
const hits = makeItem('A sponsored post', 'the body mentions sponsors', 'Ada');
const misses = makeItem('Unrelated news', 'nothing to see', 'Grace');

const probeRule = makeRule('sponsor', FilterType.FullSearch | FilterType.CaseInsensitive,
  true, ['r-true']);
check('matches reports a hit for a matching article',
  RuleEngine.matches(probeRule, hits));
check('matches reports a miss for a non-matching article',
  !RuleEngine.matches(probeRule, misses));
check('countMatches counts hits across a list',
  RuleEngine.countMatches(probeRule, [hits, misses]) === 1,
  String(RuleEngine.countMatches(probeRule, [hits, misses])));
check('countMatches of an empty list is zero',
  RuleEngine.countMatches(probeRule, []) === 0);

// The action is `r-true`, so applying the rule would flip `read`; testing it
// must not.
check('matches leaves the article untouched',
  hits.read === false && hits.starred === false && hits.hidden === false);

const appliedCopy = makeItem('A sponsored post', 'the body mentions sponsors', 'Ada');
RuleEngine.apply(probeRule, appliedCopy);
check('matches agrees with apply', appliedCopy.read === true);

const invertedRule = makeRule('sponsor', FilterType.FullSearch | FilterType.CaseInsensitive,
  false, ['r-true']);
check('an inverted rule fires on the article that lacks the pattern',
  RuleEngine.matches(invertedRule, misses));
check('an inverted rule does not fire on the article that has it',
  !RuleEngine.matches(invertedRule, hits));

section('Notification log model');
// Mirrors AppLog / AppLogType from the original's models/app.ts.

const infoLog = new AppLog(AppLogType.Info, 'Fetched 3 articles');
const failLog = new AppLog(AppLogType.Failure, 'Failed to load source "X"', 'HTTP 500');
const warnLog = new AppLog(AppLogType.Warning, 'Careful');
const articleLog = new AppLog(AppLogType.Article, 'A title', 'A source', 42);

check('an entry records when it happened', infoLog.time > 0);
check('details default to empty', infoLog.details === '');
check('info entries are not problems', !infoLog.isProblem());
check('failure entries are problems', failLog.isProblem());
check('warning entries are problems', warnLog.isProblem());
check('article entries are not problems', !articleLog.isProblem());
check('only article-referencing entries are clickable',
  articleLog.refersToArticle() && !infoLog.refersToArticle());
check('the article id is preserved', articleLog.iid === 42);
check('the severity values match the original ordering',
  AppLogType.Info === 0 && AppLogType.Warning === 1
  && AppLogType.Failure === 2 && AppLogType.Article === 3);

// A refresh outcome starts empty and accumulates.
const outcome = new RefreshOutcome();
check('a fresh outcome is empty',
  outcome.inserted === 0 && outcome.failures.length === 0 && outcome.notified.length === 0);
outcome.failures.push(new FetchFailure('Broken Source', 'A network error occurred'));
check('failures carry the source name and reason',
  outcome.failures[0].feedTitle === 'Broken Source'
  && outcome.failures[0].message.indexOf('network') >= 0);

section('Localisation runtime');
// The locale JSON is the shipped rawfile data, loaded here so the real
// messages — including ICU plurals — are what gets formatted.
const localeDir = './entry-locales';
function loadLocale(name: string): Record<string, Object> {
  const text: string = fs.readFileSync(localeDir + '/' + name + '.json', 'utf8');
  return JSON.parse(text) as Record<string, Object>;
}

const enMessages = loadLocale('en-US');
const zhMessages = loadLocale('zh-CN');
I18n.useMessages('en-US', enMessages, enMessages);

check('a plain key resolves', I18n.get('log.empty') === 'No notifications',
  I18n.get('log.empty'));
check('a nested key resolves', I18n.get('article.markRead') === 'Mark as read',
  I18n.get('article.markRead'));
check('an unknown key degrades to the key itself',
  I18n.get('no.such.key') === 'no.such.key');

// Placeholders
const named = I18n.get('log.fetchFailure', new Map<string, string | number>([
  ['name', 'Example Feed']
]));
check('a named placeholder is substituted',
  named === 'Failed to load source "Example Feed".', named);

// ICU plural, from the shipped messages
function plural(count: number): string {
  return I18n.get('log.fetchSuccess',
    new Map<string, string | number>([['count', count]]));
}
check('plural =1 uses the singular form',
  plural(1) === 'Successfully fetched 1 article.', plural(1));
check('plural other uses the plural form',
  plural(5) === 'Successfully fetched 5 articles.', plural(5));
check('plural other also covers zero',
  plural(0) === 'Successfully fetched 0 articles.', plural(0));

// Locale resolution
check('an exact locale tag is kept', I18n.normalize('zh-CN') === 'zh-CN');
check('a language-only tag maps to a region variant',
  I18n.normalize('zh') === 'zh-CN', I18n.normalize('zh'));
check('a HarmonyOS-style tag maps to the region variant',
  I18n.normalize('zh-Hans-CN') === 'zh-CN', I18n.normalize('zh-Hans-CN'));
// Only Chinese and English ship, so a traditional-Chinese tag now lands on the
// simplified pack rather than on a `zh-TW` pack this port no longer carries.
check('a traditional-Chinese tag maps to zh-CN',
  I18n.normalize('zh-Hant-TW') === 'zh-CN', I18n.normalize('zh-Hant-TW'));
check('an unmapped language falls back to English',
  I18n.normalize('de-DE') === 'en-US', I18n.normalize('de-DE'));
check('an unknown language falls back to English',
  I18n.normalize('xx-YY') === 'en-US', I18n.normalize('xx-YY'));
check('an empty tag falls back to English', I18n.normalize('') === 'en-US');
check('every bundled locale file exists',
  I18n.availableLocales().every(l =>
    fs.existsSync(localeDir + '/' + l + '.json')));
check('only Chinese and English ship',
  I18n.availableLocales().length === 2
  && I18n.availableLocales().indexOf('zh-CN') >= 0
  && I18n.availableLocales().indexOf('en-US') >= 0,
  I18n.availableLocales().join(', '));
// The two packs are the only ones on disk: a leftover pack would silently
// reappear in the language picker the moment LOCALES grew again.
const packsOnDisk: string[] = fs.readdirSync(localeDir)
  .filter((f: string) => f.endsWith('.json'));
check('no locale pack beyond the two survives on disk',
  packsOnDisk.length === 2, packsOnDisk.join(', '));
check('the language picker offers exactly two labels',
  I18n.availableLocales().every(l => I18n.localeLabel(l) !== l),
  I18n.localeLabel('zh-CN') + ' / ' + I18n.localeLabel('en-US'));

// Switching locale actually changes the output
I18n.useMessages('zh-CN', zhMessages, enMessages);
check('Chinese messages are used once installed',
  I18n.get('log.empty') === '无消息', I18n.get('log.empty'));
check('a key missing from Chinese falls back to English',
  I18n.get('nonexistent.key.only.in.en') === 'nonexistent.key.only.in.en');

// The built-in map covers strings this port adds that upstream has no key for.
I18n.useMessages('en-US', enMessages, enMessages);
check('a port-specific string resolves in English',
  I18n.get('app.noSubscriptions') === 'No subscriptions yet',
  I18n.get('app.noSubscriptions'));
check('a port-specific string with a placeholder formats',
  I18n.get('app.articlesCount', new Map<string, string | number>([['count', 7]]))
  === '7 articles');
I18n.useMessages('zh-CN', zhMessages, enMessages);
check('the same port-specific string resolves in Chinese',
  I18n.get('app.noSubscriptions') === '还没有订阅', I18n.get('app.noSubscriptions'));
check('the Chinese UI does not fall back to English for port strings',
  I18n.get('app.pickArticle').indexOf('从列表') >= 0, I18n.get('app.pickArticle'));
I18n.useMessages('en-US', enMessages, enMessages);

// Braces inside plural bodies must not break brace matching.
check('nested braces in a plural body are handled',
  I18n.get('time.minute', new Map<string, string | number>([['m', 3]]))
  === '3 minutes',
  I18n.get('time.minute', new Map<string, string | number>([['m', 3]])));

section('UI string catalogue');
// Every literal handed to I18n.get in the shipped sources must resolve, so a
// typo or an invented key cannot silently ship as raw key text in the UI.
const etsRoot: string = '../entry/src/main/ets';

function etsFiles(dir: string): string[] {
  const found: string[] = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full: string = dir + '/' + entry.name;
    if (entry.isDirectory()) {
      for (const nested of etsFiles(full)) {
        found.push(nested);
      }
    } else if (entry.name.endsWith('.ets')) {
      found.push(full);
    }
  }
  return found;
}

const uiKeys = new Set<string>();
for (const file of etsFiles(etsRoot)) {
  const text: string = fs.readFileSync(file, 'utf8');
  const re = /I18n\.get\('([^']+)'/g;
  let match = re.exec(text);
  while (match !== null) {
    uiKeys.add(match[1]);
    match = re.exec(text);
  }
}

// Keys this port adds live in the built-in catalogue inside I18n.ets, which is
// private, so its two tables are parsed straight out of the shipped source.
const i18nSource: string = fs.readFileSync(etsRoot + '/utils/I18n.ets', 'utf8');

function builtinKeys(tableName: string): string[] {
  const marker: number = i18nSource.indexOf(tableName);
  const open: number = i18nSource.indexOf('{', marker);
  const close: number = i18nSource.indexOf('\n  };', open);
  const body: string = i18nSource.slice(open, close);
  const keys: string[] = [];
  const re = /'([^']+)':/g;
  let match = re.exec(body);
  while (match !== null) {
    keys.push(match[1]);
    match = re.exec(body);
  }
  return keys;
}

const enBuiltin: string[] = builtinKeys('BUILTIN_EN');
const zhBuiltin: string[] = builtinKeys('BUILTIN_ZH');

check('the UI asks for a substantial number of catalogue keys',
  uiKeys.size > 50, String(uiKeys.size));
check('the built-in English catalogue is non-trivial',
  enBuiltin.length > 40, String(enBuiltin.length));
check('built-in English and Chinese define the same key set',
  enBuiltin.length === zhBuiltin.length
  && enBuiltin.every(k => zhBuiltin.indexOf(k) >= 0),
  'en=' + enBuiltin.length + ' zh=' + zhBuiltin.length);

const unresolved: string[] = [];
uiKeys.forEach((key: string) => {
  if (I18n.get(key) === key) {
    unresolved.push(key);
  }
});
check('every key used in the UI resolves in English',
  unresolved.length === 0, unresolved.join(', '));

// Literals that are deliberately not translated: product names, the upstream
// attribution, and an example URL. Everything else user-visible must come from
// the catalogue, so that a Chinese build is never half English.
const ALLOWED_UI_LITERALS: string[] = [
  'INOREADER',
  'Sheaf Reader 束阅',
  'Ported from Fluent Reader by yang991178',
  'https://example.com/feed.xml'
];

const stragglers: string[] = [];
for (const file of etsFiles(etsRoot)) {
  const text: string = fs.readFileSync(file, 'utf8');
  const sink =
    /(?:showToast\(\s*|Text\(\s*|Button\(\s*|title:\s*|confirmLabel:\s*|message:\s*|placeholder:\s*)'([^']{3,})'/g;
  const shortName: string = file.slice(file.lastIndexOf('/') + 1);
  let match = sink.exec(text);
  while (match !== null) {
    const value: string = match[1];
    // Internal codes (`feed_added`, `r-true`, `gf-`) are lowercase snake/action
    // keys; a user-visible string either contains a space or starts with a
    // capital. Colours and resource paths are never user-visible either.
    const looksLikeUi: boolean = (value.indexOf(' ') >= 0 || /^[A-Z]/.test(value))
      && value.indexOf('/') < 0 && value.indexOf('.ets') < 0
      && value.charAt(0) !== '#' && value.indexOf('app.media') < 0;
    if (looksLikeUi && ALLOWED_UI_LITERALS.indexOf(value) < 0) {
      stragglers.push(shortName + ': ' + value);
    }
    match = sink.exec(text);
  }
}
check('no user-visible string bypasses the catalogue',
  stragglers.length === 0, stragglers.slice(0, 6).join('  |  '));

section('Backup format');
// A backup must survive a JSON round-trip and must reject anything that is not
// one, since a wrong file would otherwise wipe the library on restore.

const backupFeed = new Feed('https://example.test/feed.xml', 'Example');
backupFeed.id = 7;
backupFeed.groupId = 3;
backupFeed.serviceRef = 'svc-1';
backupFeed.rulesJson = SourceRule.toJson([
  makeRule('AD', FilterType.None, true, ['r-true'])
]);
const backupArticle = new Article();
backupArticle.id = 99;
backupArticle.feedId = 7;
backupArticle.title = 'A title';
backupArticle.read = true;

const backupJson = JSON.stringify({
  format: BackupFile.FORMAT,
  version: 1,
  exportedAt: 1700000000000,
  settings: { 'theme': '2', 'locale': 'zh-CN' },
  groups: [{ id: 3, name: 'Tech' }],
  feeds: [backupFeed],
  articles: [backupArticle]
});

const described = BackupService.describe(backupJson);
check('a valid backup is described', described !== null && described.ok);
if (described !== null) {
  check('the feed count is reported', described.feeds === 1,
    String(described.feeds));
  check('the article count is reported', described.articles === 1,
    String(described.articles));
  check('the group count is reported', described.groups === 1,
    String(described.groups));
}

// The negative cases below make the parser log deliberately; silence that so
// a passing run stays readable and does not look like a failure.
const realConsoleError = console.error;
console.error = () => {
};

check('a foreign JSON file is rejected',
  BackupService.describe('{"hello":"world"}') === null);
check('a JSON array is rejected', BackupService.describe('[]') === null);
check('malformed JSON is rejected', BackupService.describe('{not json') === null);
check('an empty file is rejected', BackupService.describe('') === null);
check('a file with no feeds array is rejected',
  BackupService.describe('{"format":"sheaf-reader-hm"}') === null);
// The project was renamed (Fluent Reader for HarmonyOS -> Sheaf Reader); a
// backup exported before the rename carries the old marker and must keep
// restoring instead of being rejected as a foreign file.
check('a backup written under the pre-rename marker is still accepted',
  BackupService.describe('{"format":"fluent-reader-hm","feeds":[],"groups":[],"articles":[]}') !== null
  && BackupFile.LEGACY_FORMAT !== BackupFile.FORMAT);
check('a foreign format marker is still rejected',
  BackupService.describe('{"format":"fluent-reader","feeds":[],"articles":[]}') === null);

console.error = realConsoleError;

// Feed fields the backup must carry, including the ones added for sync.
const roundTripped = JSON.parse(backupJson) as Record<string, Object>;
const feedsOut = roundTripped['feeds'] as Feed[];
check('a backup keeps the feed url', feedsOut[0].url === 'https://example.test/feed.xml');
check('a backup keeps the service ref', feedsOut[0].serviceRef === 'svc-1');
check('a backup keeps the per-source rules',
  SourceRule.fromJson(feedsOut[0].rulesJson).length === 1);
check('a backup keeps article read state',
  (roundTripped['articles'] as Article[])[0].read === true);

section('UrlUtils');
check('absolute detected', UrlUtils.isAbsolute('https://a.test/x'));
check('relative rejected', !UrlUtils.isAbsolute('/x'));
check('scheme added',
  UrlUtils.normalize('example.com/feed') === 'https://example.com/feed',
  UrlUtils.normalize('example.com/feed'));
check('existing scheme preserved',
  UrlUtils.normalize('http://a.test') === 'http://a.test');
check('origin extracted', UrlUtils.origin('https://a.test:8080/p?q=1') === 'https://a.test:8080',
  UrlUtils.origin('https://a.test:8080/p?q=1'));
check('root-relative resolved',
  UrlUtils.resolve('https://a.test/blog/post', '/feed.xml') === 'https://a.test/feed.xml',
  UrlUtils.resolve('https://a.test/blog/post', '/feed.xml'));
check('path-relative resolved',
  UrlUtils.resolve('https://a.test/blog/post', 'feed.xml') === 'https://a.test/blog/feed.xml',
  UrlUtils.resolve('https://a.test/blog/post', 'feed.xml'));
check('protocol-relative resolved',
  UrlUtils.resolve('https://a.test/blog', '//cdn.test/f.xml') === 'https://cdn.test/f.xml',
  UrlUtils.resolve('https://a.test/blog', '//cdn.test/f.xml'));
check('absolute reference untouched',
  UrlUtils.resolve('https://a.test/', 'https://b.test/f') === 'https://b.test/f');
check('query string stripped when resolving',
  UrlUtils.resolve('https://a.test/blog?page=2', 'feed.xml') === 'https://a.test/feed.xml',
  UrlUtils.resolve('https://a.test/blog?page=2', 'feed.xml'));

section('Feed discovery heuristics');
check('rss detected', FeedFetcher.looksLikeFeed('<rss version="2.0">'));
check('atom detected', FeedFetcher.looksLikeFeed('<feed xmlns="...">'));
check('rdf detected', FeedFetcher.looksLikeFeed('<rdf:RDF>'));
check('html not a feed', !FeedFetcher.looksLikeFeed('<html><body>x</body></html>'));

section('Full content extraction');
// "Load full content" pulls the article body out of the linked web page. The
// original uses Mercury / Postlight; this port scores blocks textually, so the
// assertions below pin the behaviour that heuristic must preserve: keep the
// prose, drop the chrome, and fail loudly rather than store an empty body.

const ARTICLE_PAGE = `<!DOCTYPE html>
<html><head>
<title>Widget Engineering Weekly</title>
<script>window.analytics = { mark: 'SCRIPT_MARKER' };</script>
<style>.ad { display: none; }</style>
</head>
<body>
<nav><a href="/home">Home</a><a href="/pricing">Pricing plans</a></nav>
<header><h1>Widget Engineering Weekly</h1><p>Subscribe to our newsletter</p></header>
<main>
<article>
<h2>Shipping a scheduler in ArkTS</h2>
<p>Last quarter we replaced the hand-rolled timer wheel with a proper scheduler, and the change removed an entire class of latency spikes that had been haunting the ingest path for months.</p>
<p>Our R&amp;D team measured the ingest path before touching it, which is the only reason we knew the spikes were bookkeeping rather than network time.</p>
<p>The new design keeps a single hierarchical timing wheel. Adding a connection is now a constant-time insertion, and cancelling one is a single unlink from a doubly linked list.</p>
<blockquote>Measure first, then optimise the thing you measured.</blockquote>
</article>
</main>
<aside><h3>Related posts</h3><a href="/a">A related post title that is quite long indeed</a></aside>
<footer><p>Copyright 2026 Widget Engineering Weekly. All rights reserved worldwide.</p></footer>
</body></html>`;

const extracted = ContentExtractor.extract(ARTICLE_PAGE);
const extractedHtml: string = extracted === null ? '' : extracted.html;

check('a real page shape yields an extraction', extracted !== null);
check('the extracted body carries the prose',
  extractedHtml.indexOf('hierarchical timing wheel') >= 0);
check('a heading survives extraction',
  extractedHtml.indexOf('Shipping a scheduler in ArkTS') >= 0,
  extractedHtml.slice(0, 120));
check('a pull quote survives extraction',
  extractedHtml.indexOf('Measure first') >= 0);
check('script contents never reach the body',
  extractedHtml.indexOf('SCRIPT_MARKER') < 0);
check('style contents never reach the body',
  extractedHtml.indexOf('display: none') < 0);
check('navigation is dropped', extractedHtml.indexOf('Pricing plans') < 0);
check('a page footer is dropped', extractedHtml.indexOf('Copyright 2026') < 0);
check('a related-posts sidebar is dropped', extractedHtml.indexOf('Related posts') < 0);
check('entities in the body are decoded', extractedHtml.indexOf('R&D') >= 0,
  extractedHtml.indexOf('R&amp;D') >= 0 ? 'left encoded' : 'missing');
check('the reported length is the visible text length',
  extracted !== null && extracted.textLength > 400,
  extracted === null ? 'null' : String(extracted.textLength));

// Without <article>/<main> the block heuristic has to do the work itself.
const FLAT_PAGE = `<html><body>
<div class="menu"><a href="/1">First navigation entry</a><a href="/2">Second navigation entry</a><a href="/3">Third navigation entry</a></div>
<div>Photo credit: A. Smith</div>
<p>A sufficiently long opening paragraph that discusses the subject at hand and contains several sentences. It continues for long enough that the density heuristic accepts it as prose rather than as a label.</p>
<p>A second paragraph of comparable length, also containing several sentences, so that the combined visible text clears the minimum total length that an accepted extraction requires.</p>
</body></html>`;

const flat = ContentExtractor.extract(FLAT_PAGE);
const flatHtml: string = flat === null ? '' : flat.html;
check('a page without semantic landmarks still extracts', flat !== null);
check('a link-heavy block is dropped',
  flatHtml.indexOf('First navigation entry') < 0, flatHtml.slice(0, 160));
check('a caption below the block minimum is dropped',
  flatHtml.indexOf('Photo credit') < 0);
check('the prose keeps document order',
  flatHtml.indexOf('opening paragraph') < flatHtml.indexOf('second paragraph'));

const ONLY_CHROME = `<html><body>
<nav><a href="/a">Home</a></nav>
<footer><p>Copyright 2026 Somebody. All rights reserved worldwide here.</p></footer>
</body></html>`;
check('a page with no prose yields nothing',
  ContentExtractor.extract(ONLY_CHROME) === null);

const TOO_SHORT = `<html><body><article>
<p>Only one short sentence lives here.</p>
</article></body></html>`;
check('prose below the minimum total length is rejected',
  ContentExtractor.extract(TOO_SHORT) === null);
check('empty input is rejected', ContentExtractor.extract('') === null);

section('Sync service endpoint bases');
// Each service derives its API base from whatever the user typed, so the
// normalisers must be idempotent — a stored endpoint is fed back in on every
// later sync and must not grow a second `/v1/` or app path.
check('an empty Miniflux endpoint stays empty', HttpClient.minifluxBase('') === '');
check('a Miniflux root gains /v1/',
  HttpClient.minifluxBase('https://m.test') === 'https://m.test/v1/',
  HttpClient.minifluxBase('https://m.test'));
check('a Miniflux base already carrying /v1/ is left alone',
  HttpClient.minifluxBase('https://m.test/v1/') === 'https://m.test/v1/');
check('a Miniflux endpoint with a subpath keeps it',
  HttpClient.minifluxBase('https://m.test/miniflux') === 'https://m.test/miniflux/v1/',
  HttpClient.minifluxBase('https://m.test/miniflux'));

check('an empty Feedbin endpoint means the public API host',
  HttpClient.feedbinBase('') === 'https://api.feedbin.com/v2/',
  HttpClient.feedbinBase(''));
check('a Feedbin root gains /v2/',
  HttpClient.feedbinBase('http://127.0.0.1:8899') === 'http://127.0.0.1:8899/v2/',
  HttpClient.feedbinBase('http://127.0.0.1:8899'));
check('a Feedbin base already carrying /v2/ is left alone',
  HttpClient.feedbinBase('https://api.feedbin.com/v2/') === 'https://api.feedbin.com/v2/');

check('an empty Nextcloud endpoint stays empty', HttpClient.nextcloudBase('') === '');
check('a Nextcloud instance root gains the News app path',
  HttpClient.nextcloudBase('https://cloud.test')
  === 'https://cloud.test/index.php/apps/news/api/v1-3/',
  HttpClient.nextcloudBase('https://cloud.test'));
check('a Nextcloud endpoint already carrying the app path is left alone',
  HttpClient.nextcloudBase('https://cloud.test/index.php/apps/news/api/v1-3/')
  === 'https://cloud.test/index.php/apps/news/api/v1-3/',
  HttpClient.nextcloudBase('https://cloud.test/index.php/apps/news/api/v1-3/'));
check('a Nextcloud instance installed under a subpath keeps it',
  HttpClient.nextcloudBase('https://host.test/nextcloud')
  === 'https://host.test/nextcloud/index.php/apps/news/api/v1-3/',
  HttpClient.nextcloudBase('https://host.test/nextcloud'));

check('an empty Fever endpoint stays empty', HttpClient.feverBase('') === '');
check('a bare Fever host gains the /fever/ path',
  HttpClient.feverBase('https://host.test') === 'https://host.test/fever/?api',
  HttpClient.feverBase('https://host.test'));
check('a Fever host with a trailing slash is not doubled',
  HttpClient.feverBase('https://host.test/') === 'https://host.test/fever/?api',
  HttpClient.feverBase('https://host.test/'));
check('a Fever endpoint already carrying /fever/ is left alone',
  HttpClient.feverBase('https://host.test/fever/') === 'https://host.test/fever/?api');
check('the documented Fever URL is idempotent',
  HttpClient.feverBase('https://host.test/fever/?api') === 'https://host.test/fever/?api',
  HttpClient.feverBase('https://host.test/fever/?api'));
check('a FreshRSS-style fever.php endpoint is accepted',
  HttpClient.feverBase('https://host.test/api/fever.php')
  === 'https://host.test/api/fever.php?api',
  HttpClient.feverBase('https://host.test/api/fever.php'));
check('a fever.php URL that already has ?api is idempotent',
  HttpClient.feverBase('https://host.test/api/fever.php?api')
  === 'https://host.test/api/fever.php?api',
  HttpClient.feverBase('https://host.test/api/fever.php?api'));

section('Manual list ordering');
// The sidebar's drag-and-drop reorder is this one function, so the move maths
// is pinned here as well as on a device.
const ORDER: string[] = ['a', 'b', 'c', 'd'];
const forward = moveItem(ORDER, 0, 2) ?? [];
check('a forward move lands the item at the target index',
  forward.join('') === 'bcad', forward.join(''));
const backward = moveItem(ORDER, 3, 1) ?? [];
check('a backward move lands the item at the target index',
  backward.join('') === 'adbc', backward.join(''));
check('moving an item onto itself is a no-op', moveItem(ORDER, 2, 2) === null);
check('an out-of-range source index is rejected',
  moveItem(ORDER, -1, 1) === null && moveItem(ORDER, 4, 1) === null);
check('an out-of-range target index is rejected',
  moveItem(ORDER, 1, -1) === null && moveItem(ORDER, 1, 4) === null);
check('the source array is left untouched', ORDER.join('') === 'abcd', ORDER.join(''));
const movedAll = moveItem(ORDER, 0, 3) ?? [];
check('a move neither loses nor duplicates an element',
  movedAll.length === ORDER.length
  && ORDER.every(x => movedAll.indexOf(x) >= 0),
  movedAll.join(''));

const rows: Identified[] = [{ id: 3 }, { id: 1 }, { id: 2 }];
check('idsOf preserves list order', idsOf(rows).join(',') === '3,1,2',
  idsOf(rows).join(','));
check('idsOf of an empty list is empty', idsOf([]).length === 0);

section('Image file names');
// "Save image as …" hands this name to the system picker, so a bad derivation
// would pre-fill the dialog with something unusable.
const nameOf = ImageActions.suggestedFileName;
check('a plain image URL keeps its name',
  nameOf('https://x.test/a/photo.jpg') === 'photo.jpg', nameOf('https://x.test/a/photo.jpg'));
check('a query string is dropped',
  nameOf('https://x.test/a/photo.png?w=100&h=50') === 'photo.png',
  nameOf('https://x.test/a/photo.png?w=100&h=50'));
check('a fragment is dropped',
  nameOf('https://x.test/a/photo.jpeg#frag') === 'photo.jpeg',
  nameOf('https://x.test/a/photo.jpeg#frag'));
check('an uppercased extension is accepted',
  nameOf('https://x.test/a/PHOTO.PNG') === 'PHOTO.PNG',
  nameOf('https://x.test/a/PHOTO.PNG'));
check('percent-encoding is decoded for the user',
  nameOf('https://x.test/a/my%20pic.png') === 'my pic.png',
  nameOf('https://x.test/a/my%20pic.png'));
check('a malformed escape does not throw',
  nameOf('https://x.test/a/bad%zz.png').endsWith('.png'),
  nameOf('https://x.test/a/bad%zz.png'));

check('a directory URL falls back', nameOf('https://x.test/a/') === 'image.png',
  nameOf('https://x.test/a/'));
check('an extensionless name falls back',
  nameOf('https://x.test/a/photo') === 'image.png', nameOf('https://x.test/a/photo'));
check('a non-image extension falls back',
  nameOf('https://x.test/a/notes.txt') === 'image.png', nameOf('https://x.test/a/notes.txt'));
check('a dotfile falls back', nameOf('https://x.test/a/.hidden') === 'image.png',
  nameOf('https://x.test/a/.hidden'));
check('an empty URL falls back', nameOf('') === 'image.png');

section('Search engine URLs');
// These back "search selected text"; each engine takes a different parameter,
// and a selection with spaces or CJK must survive the trip to the browser.
const urlFor = SearchEngines.urlFor;
check('Google takes q',
  urlFor(SearchEngine.Google, 'arkts') === 'https://www.google.com/search?q=arkts',
  urlFor(SearchEngine.Google, 'arkts'));
check('Bing takes q',
  urlFor(SearchEngine.Bing, 'arkts') === 'https://www.bing.com/search?q=arkts',
  urlFor(SearchEngine.Bing, 'arkts'));
check('Baidu takes wd',
  urlFor(SearchEngine.Baidu, 'arkts') === 'https://www.baidu.com/s?wd=arkts',
  urlFor(SearchEngine.Baidu, 'arkts'));
check('DuckDuckGo takes q',
  urlFor(SearchEngine.DuckDuckGo, 'arkts') === 'https://duckduckgo.com/?q=arkts',
  urlFor(SearchEngine.DuckDuckGo, 'arkts'));

check('a multi-word selection is percent-encoded',
  urlFor(SearchEngine.Google, 'hello world')
  === 'https://www.google.com/search?q=hello%20world',
  urlFor(SearchEngine.Google, 'hello world'));
check('a CJK selection is percent-encoded',
  urlFor(SearchEngine.Baidu, '中文')
  === 'https://www.baidu.com/s?wd=%E4%B8%AD%E6%96%87',
  urlFor(SearchEngine.Baidu, '中文'));
check('an ampersand in the selection cannot break out of the query',
  urlFor(SearchEngine.Google, 'a&b').indexOf('&b') < 0,
  urlFor(SearchEngine.Google, 'a&b'));
check('an unknown engine falls back to Google',
  urlFor(99, 'x') === 'https://www.google.com/search?q=x');

check('every engine has a catalogue label key',
  SearchEngines.ALL.every(e => SearchEngines.labelKey(e).startsWith('searchEngine.')),
  SearchEngines.ALL.map(e => SearchEngines.labelKey(e)).join(','));
check('all four engines are offered', SearchEngines.ALL.length === 4,
  String(SearchEngines.ALL.length));

// --- "Search selected text": range -> query -> menu label --------------------
// The selection menu hands back a TextRange measured against the rendered body,
// so these two pure helpers are exactly what stands between the platform's
// indices and the URL that reaches the browser.
const selectionOf = SearchEngines.selectionOf;
//             0123456789012345678
const body = 'hello world, 你好世界';
check('a range maps back to its substring',
  selectionOf(body, 6, 11) === 'world', selectionOf(body, 6, 11));
check('surrounding whitespace is trimmed',
  selectionOf(body, 5, 11) === 'world', selectionOf(body, 5, 11));
check('a CJK range survives',
  selectionOf(body, 13, 17) === '你好世界', selectionOf(body, 13, 17));
check('an empty range selects nothing',
  selectionOf(body, 5, 5) === '', JSON.stringify(selectionOf(body, 5, 5)));
check('a reversed range selects nothing',
  selectionOf(body, 11, 5) === '', JSON.stringify(selectionOf(body, 11, 5)));
check('a range running past the body is clamped',
  selectionOf(body, 13, 9999) === '你好世界', selectionOf(body, 13, 9999));
check('a negative start is clamped to zero',
  selectionOf(body, -5, 5) === 'hello', selectionOf(body, -5, 5));

// The label is what the platform renders in the menu, and the engine name has
// to arrive through a second lookup rather than staying a raw key.
check('the menu label names the selection and the engine',
  SearchEngines.menuLabel(SearchEngine.Google, 'arkts')
    === 'Search "arkts" on Google',
  SearchEngines.menuLabel(SearchEngine.Google, 'arkts'));
check('the menu label follows the engine',
  SearchEngines.menuLabel(SearchEngine.Baidu, 'arkts')
    === 'Search "arkts" on Baidu',
  SearchEngines.menuLabel(SearchEngine.Baidu, 'arkts'));
check('an empty selection still yields a readable label',
  SearchEngines.menuLabel(SearchEngine.Google, '').indexOf('...') > 0,
  SearchEngines.menuLabel(SearchEngine.Google, ''));
check('a whitespace-only selection is treated as empty',
  SearchEngines.menuLabel(SearchEngine.Google, '   ').indexOf('...') > 0,
  SearchEngines.menuLabel(SearchEngine.Google, '   '));
check('the menu label never leaks a raw catalogue key',
  SearchEngines.menuLabel(SearchEngine.DuckDuckGo, 'x').indexOf('context.search') < 0,
  SearchEngines.menuLabel(SearchEngine.DuckDuckGo, 'x'));

// The menu label and the URL must agree about what was selected: the exact
// string shown in the menu is the exact string sent to the engine.
check('the label and the URL describe the same query',
  SearchEngines.urlFor(SearchEngine.Google, selectionOf(body, 6, 11))
    === 'https://www.google.com/search?q=world');

// --- Storage accounting ------------------------------------------------------
// These back the settings "Clean up" hints: "Around {size} of local storage is
// occupied by articles" and the cache size. `byteLength` is the original's own
// approximation of UTF-8 length, so its exact behaviour on multibyte text is
// part of the contract rather than an implementation detail.
section('Storage accounting');
const byteLength = StorageSize.byteLength;

check('ASCII counts one byte per character', byteLength('abc') === 3,
  String(byteLength('abc')));
check('an empty string is zero bytes', byteLength('') === 0,
  String(byteLength('')));
check('a two-byte character adds one', byteLength('é') === 2,
  String(byteLength('é')));
check('a three-byte CJK character counts three', byteLength('中') === 3,
  String(byteLength('中')));
check('a three-byte symbol counts three', byteLength('€') === 3,
  String(byteLength('€')));
check('an astral character counts four, not six', byteLength('😀') === 4,
  String(byteLength('😀')));
check('mixed text sums per character', byteLength('a中b') === 5,
  String(byteLength('a中b')));
check('CJK text measures larger than the same length of ASCII',
  byteLength('中中中') > byteLength('abc'),
  byteLength('中中中') + ' vs ' + byteLength('abc'));

check('a byte count under half a megabyte rounds down to 0MB',
  StorageSize.formatMb(524287) === '0MB', StorageSize.formatMb(524287));
check('a byte count at half a megabyte rounds up to 1MB',
  StorageSize.formatMb(524288) === '1MB', StorageSize.formatMb(524288));
check('an empty store reads 0MB', StorageSize.formatMb(0) === '0MB',
  StorageSize.formatMb(0));
check('exactly one megabyte reads 1MB',
  StorageSize.formatMb(1048576) === '1MB', StorageSize.formatMb(1048576));
check('one byte short of two megabytes rounds up to 2MB, not down to 1MB',
  StorageSize.formatMb(2097151) === '2MB', StorageSize.formatMb(2097151));
check('a megabyte and a half rounds to 2MB',
  StorageSize.formatMb(1572864) === '2MB', StorageSize.formatMb(1572864));
// The cache button is disabled by comparing the formatted string to "0MB", so
// that exact spelling is load-bearing rather than cosmetic.
check('the zero rendering is exactly 0MB',
  StorageSize.formatMb(1) === '0MB', StorageSize.formatMb(1));

function art(o: Partial<Article>): Article {
  return Object.assign(new Article(), o) as Article;
}

const smallArticle = art({ id: 1, title: 'Hello' });
const bigArticle = art({ id: 2, title: 'Hello', content: 'x'.repeat(400) });
const cjkArticle = art({ id: 3, title: '你好' });

check('a serialized row is valid JSON',
  JSON.parse(StorageSize.serialized(smallArticle)) !== null);
check('a serialized row carries the title',
  StorageSize.serialized(smallArticle).indexOf('Hello') > 0);
check('the same row serializes identically twice',
  StorageSize.serialized(smallArticle) === StorageSize.serialized(smallArticle));
check('a different row serializes differently',
  StorageSize.serialized(smallArticle) !== StorageSize.serialized(bigArticle));
check('serialization is stable in field order, not just content',
  StorageSize.serialized(smallArticle).indexOf('"title"')
    < StorageSize.serialized(smallArticle).indexOf('"content"'),
  StorageSize.serialized(smallArticle).slice(0, 60));

check('one article totals its own serialized size',
  StorageSize.totalBytes([smallArticle])
    === byteLength(StorageSize.serialized(smallArticle)),
  String(StorageSize.totalBytes([smallArticle])));
check('an empty store totals zero', StorageSize.totalBytes([]) === 0,
  String(StorageSize.totalBytes([])));
check('two articles total the sum of both',
  StorageSize.totalBytes([smallArticle, bigArticle])
    === StorageSize.totalBytes([smallArticle]) + StorageSize.totalBytes([bigArticle]));
check('a longer article weighs more',
  StorageSize.totalBytes([bigArticle]) > StorageSize.totalBytes([smallArticle]),
  StorageSize.totalBytes([bigArticle]) + ' vs ' + StorageSize.totalBytes([smallArticle]));
check('CJK content weighs more than the same character count of ASCII',
  StorageSize.totalBytes([cjkArticle]) > StorageSize.totalBytes([art({ id: 4, title: 'ab' })]),
  StorageSize.totalBytes([cjkArticle]) + ' vs ' + StorageSize.totalBytes([art({ id: 4, title: 'ab' })]));


// --- Day bounds for the date-based menus -------------------------------------
// "Delete articles from N days ago" and "mark articles from N days ago as read"
// both convert a day count into a publication-date bound. The two differ in what
// day 0 means (now vs. no bound at all), so only the conversion is shared and
// its literal arithmetic is pinned here.
section('Day bounds');
const dayMs = 24 * 60 * 60 * 1000;
const now = 1758326400000;

check('zero days is the reference instant, not the epoch',
  TimeBounds.daysAgo(0, now) === now, String(TimeBounds.daysAgo(0, now)));
check('one day back is exactly 24 hours',
  TimeBounds.daysAgo(1, now) === now - dayMs, String(TimeBounds.daysAgo(1, now)));
check('three days back',
  TimeBounds.daysAgo(3, now) === now - 3 * dayMs, String(TimeBounds.daysAgo(3, now)));
check('seven days back',
  TimeBounds.daysAgo(7, now) === now - 7 * dayMs, String(TimeBounds.daysAgo(7, now)));
check('twenty-eight days back',
  TimeBounds.daysAgo(28, now) === now - 28 * dayMs, String(TimeBounds.daysAgo(28, now)));
check('a larger day count gives an earlier bound',
  TimeBounds.daysAgo(28, now) < TimeBounds.daysAgo(7, now));
check('the arithmetic is literal, with no clamping at zero',
  TimeBounds.daysAgo(100000, now) < 0, String(TimeBounds.daysAgo(100000, now)));

// --- Source scopes for the group / source context menu -----------------------
// The same rule decides which sources the menu marks as read and which ones a
// scoped refresh fetches, so getting it wrong silently widens a per-source
// action into a library-wide one.
section('Source scopes');
function fd(id: number, groupId: number): Feed {
  const feed = new Feed();
  feed.id = id;
  feed.groupId = groupId;
  return feed;
}
const scopeFeeds: Feed[] = [fd(1, 10), fd(2, 10), fd(3, 20), fd(4, -1)];

check('a source scope selects only that source',
  ScopeFilter.feedIds(scopeFeeds, -1, 2).join(',') === '2',
  ScopeFilter.feedIds(scopeFeeds, -1, 2).join(','));
check('a group scope selects every source in the group',
  ScopeFilter.feedIds(scopeFeeds, 10, -1).join(',') === '1,2',
  ScopeFilter.feedIds(scopeFeeds, 10, -1).join(','));
check('a group with one source',
  ScopeFilter.feedIds(scopeFeeds, 20, -1).join(',') === '3',
  ScopeFilter.feedIds(scopeFeeds, 20, -1).join(','));
check('an ungrouped source is addressable by id',
  ScopeFilter.feedIds(scopeFeeds, -1, 4).join(',') === '4',
  ScopeFilter.feedIds(scopeFeeds, -1, 4).join(','));
check('an unknown source id selects nothing',
  ScopeFilter.feedIds(scopeFeeds, -1, 99).length === 0,
  ScopeFilter.feedIds(scopeFeeds, -1, 99).join(','));
check('an empty group selects nothing',
  ScopeFilter.feedIds(scopeFeeds, 30, -1).length === 0,
  ScopeFilter.feedIds(scopeFeeds, 30, -1).join(','));
check('with neither set the scope is every source',
  ScopeFilter.feedIds(scopeFeeds, -1, -1).length === 4,
  ScopeFilter.feedIds(scopeFeeds, -1, -1).join(','));

check('an unscoped refresh contains everything',
  ScopeFilter.contains(null, 7) && ScopeFilter.contains(null, 0));
check('a scoped refresh contains only its members',
  ScopeFilter.contains([1, 2], 2) && !ScopeFilter.contains([1, 2], 3));
// `null` and `[]` are deliberately different: the first means "no scope", the
// second means "a scope that happens to be empty", which selects nothing.
check('an empty scope is not the same as no scope',
  !ScopeFilter.contains([], 7), String(ScopeFilter.contains([], 7)));

// --- Loaded article pages ----------------------------------------------------
// "Load full content" and "Load webpage" are view state, not stored data: the
// mode code below is what makes them toggle back to the feed's own text.
section('Loaded article pages');
const verbatimPage = new LoadedPage();
verbatimPage.body = '<html>page</html>';
const extractedPage = new LoadedPage();
extractedPage.body = '<p>body</p>';
extractedPage.extracted = true;

check('a verbatim page reports mode 0', verbatimPage.mode() === 0, String(verbatimPage.mode()));
check('an extracted page reports mode 1', extractedPage.mode() === 1, String(extractedPage.mode()));
check('the two modes differ, so the toggle can tell them apart',
  verbatimPage.mode() !== extractedPage.mode());
check('"nothing loaded" is a distinct code from both modes',
  -1 !== verbatimPage.mode() && -1 !== extractedPage.mode());

// --- Desktop shortcut coverage ----------------------------------------------
// The shortcut table is wide enough that a branch can vanish unnoticed, so its
// key set is pinned against the shipped handler rather than trusted.
section('Desktop shortcut coverage');
const indexSource: string = fs.readFileSync(etsRoot + '/pages/Index.ets', 'utf8');
const articleKeys: string[] = ['M', 'S', 'B', 'H', 'L', 'W'];
for (const key of articleKeys) {
  check('the ' + key + ' article shortcut is handled',
    new RegExp('KEYCODE_' + key + '\\b').test(indexSource));
}
const functionKeys: string[] = ['F2', 'F5', 'F6', 'F7', 'F9'];
for (const key of functionKeys) {
  check('the ' + key + ' function shortcut is handled',
    new RegExp('KEYCODE_' + key + '\\b').test(indexSource));
}
check('the list movement keys are handled',
  /KEYCODE_J\b/.test(indexSource) && /KEYCODE_K\b/.test(indexSource)
  && /KEYCODE_DPAD_LEFT\b/.test(indexSource) && /KEYCODE_DPAD_RIGHT\b/.test(indexSource));
check('Escape still leaves the reader', /KEYCODE_ESCAPE\b/.test(indexSource));

// --- Sidebar "unread sources only" filter ------------------------------------
// With the filter on, empty sources disappear and a group disappears once all of
// its sources are empty; with it off nothing is hidden.
section('Sidebar unread-sources filter');
function sf(id: number, unreadCount: number): Feed {
  const feed = new Feed();
  feed.id = id;
  feed.unreadCount = unreadCount;
  return feed;
}
const sfFeeds: Feed[] = [sf(1, 0), sf(2, 3), sf(3, 0)];

check('with the filter off an empty source is listed',
  SourceFilter.visible(sf(1, 0), false));
check('with the filter off a non-empty source is listed',
  SourceFilter.visible(sf(2, 3), false));
check('with the filter on a non-empty source is listed',
  SourceFilter.visible(sf(2, 3), true));
check('with the filter on an empty source is hidden',
  !SourceFilter.visible(sf(1, 0), true));
check('with the filter off every source survives',
  SourceFilter.filter(sfFeeds, false).length === 3,
  String(SourceFilter.filter(sfFeeds, false).length));
check('with the filter on only the non-empty ones survive',
  SourceFilter.filter(sfFeeds, true).map(f => f.id).join(',') === '2',
  SourceFilter.filter(sfFeeds, true).map(f => f.id).join(','));

check('a group with an unread source is listed',
  SourceFilter.groupVisible(sfFeeds, true));
check('a group whose sources are all read is hidden',
  !SourceFilter.groupVisible([sf(1, 0), sf(3, 0)], true));
check('an empty group is hidden while filtering',
  !SourceFilter.groupVisible([], true));
check('an empty group is listed when not filtering',
  SourceFilter.groupVisible([], false));

// --- Sidebar visibility ------------------------------------------------------
// The original's `getWindowBreakpoint() && getDefaultMenu()`: the stored choice
// only survives on a window wide enough to host the sidebar as a column.
section('Sidebar visibility');
check('the breakpoint is 1440vp', SIDEBAR_BREAKPOINT === 1440, String(SIDEBAR_BREAKPOINT));
check('a stored "shown" survives on a wide window',
  SidebarState.initial(true, 1448));
check('a stored "shown" survives exactly at the breakpoint',
  SidebarState.initial(true, SIDEBAR_BREAKPOINT));
check('a stored "shown" is dropped one vp below the breakpoint',
  !SidebarState.initial(true, SIDEBAR_BREAKPOINT - 1));
check('a stored "hidden" stays hidden on a wide window',
  !SidebarState.initial(false, 2000));
check('a stored "hidden" stays hidden on a narrow window',
  !SidebarState.initial(false, 800));
check('the gate never turns a hidden sidebar on',
  !SidebarState.initial(false, 0) && !SidebarState.initial(false, 4000));

// --- Sidebar as a column vs. as a drawer -------------------------------------
// `menu.tsx`: at or above 1440px the sidebar is a fixed 280px column laid out
// in the page; below it the same panel is an overlay whose container claims no
// layout width, so the list underneath is never squeezed. Getting this wrong is
// invisible at one window size and obvious at the other, so it is pinned here.
section('Sidebar column / drawer geometry');
check('the panel is a fixed 280vp, not a proportion',
  SidebarState.layoutWidth(true, 1440) === 280
  && SidebarState.layoutWidth(true, 3840) === 280,
  String(SidebarState.layoutWidth(true, 3840)));
check('an open sidebar claims layout width on a wide window',
  SidebarState.layoutWidth(true, 1448) === SIDEBAR_WIDTH);
check('a closed sidebar claims none', SidebarState.layoutWidth(false, 2000) === 0);
check('an open drawer claims none, so the list is not squeezed',
  SidebarState.layoutWidth(true, SIDEBAR_BREAKPOINT - 1) === 0);
check('the drawer branch starts exactly one vp below the breakpoint',
  SidebarState.layoutWidth(true, SIDEBAR_BREAKPOINT - 1) === 0
  && SidebarState.layoutWidth(true, SIDEBAR_BREAKPOINT) === SIDEBAR_WIDTH);
check('"wide" is the breakpoint, inclusive',
  SidebarState.isWide(SIDEBAR_BREAKPOINT)
  && !SidebarState.isWide(SIDEBAR_BREAKPOINT - 1));
// `SELECT_PAGE` receives `keepMenu: getWindowBreakpoint()`.
check('selecting a page keeps the column on a wide window',
  SidebarState.keepsMenuOnSelect(2000));
check('selecting a page dismisses the drawer on a narrow window',
  !SidebarState.keepsMenuOnSelect(1200)
  && !SidebarState.keepsMenuOnSelect(SIDEBAR_BREAKPOINT - 1));

// --- Upstream locale coverage -------------------------------------------------
// The strings the port used to invent are now the original's own keys wherever
// the original has one, which is what keeps them consistent with the upstream
// `en-US` / `zh-CN` packs this port ships.
// These pin the mapping and stop it from silently regressing.
section('Upstream locale coverage');
const upstreamKeys: string[] = [
  'article.markRead', 'article.markUnread', 'article.star', 'article.unstar',
  'article.hide', 'article.unhide', 'article.notify', 'article.dontNotify',
  'rules.title', 'rules.fullSearch', 'rules.creator', 'rules.match', 'rules.notMatch',
  'time.minute', 'time.hour', 'sources.unlimited', 'service.fetchUnlimited',
  'sources.add', 'groups.enterName'
];
for (const key of upstreamKeys) {
  check('the upstream pack defines ' + key, I18n.get(key) !== key, I18n.get(key));
}

/** Flat key set of a loaded locale object. */
function flatKeys(root: Record<string, Object>): Set<string> {
  const keys = new Set<string>();
  const walk = (o: Record<string, Object>, prefix: string): void => {
    for (const k of Object.keys(o)) {
      const v = o[k] as Object;
      const path: string = prefix.length === 0 ? k : prefix + '.' + k;
      if (v !== null && typeof v === 'object') {
        walk(v as Record<string, Object>, path);
      } else {
        keys.add(path);
      }
    }
  };
  walk(root, '');
  return keys;
}

const upstreamFlat: Set<string> = flatKeys(enMessages);
const replacedByUpstream: string[] = [
  'app.markRead', 'app.markUnread', 'app.star', 'app.unstar', 'app.hide', 'app.unhide',
  'app.notify', 'app.dontNotify', 'app.title', 'app.titleOrContent', 'app.matches',
  'app.notMatches', 'app.author', 'app.unlimited', 'app.addFeed', 'app.enterGroupName',
  'app.minutes15', 'app.minutes30', 'app.hour1', 'app.hours2', 'app.hours4', 'app.hours12'
];
const stillReferenced: string[] = [];
for (const file of etsFiles(etsRoot)) {
  const text: string = fs.readFileSync(file, 'utf8');
  for (const key of replacedByUpstream) {
    if (text.indexOf("I18n.get('" + key + "'") >= 0) {
      stillReferenced.push(key + ' @ ' + file);
    }
  }
}
check('the port no longer asks for the strings it replaced',
  stillReferenced.length === 0, stillReferenced.join(', '));

// --- Bilingual completeness ---------------------------------------------------
// Only two locales ship, so the promise is now "both bundled languages are
// complete" rather than "English is complete and 17 others degrade to English".
// Every catalogue key in the upstream pack must therefore also be in the
// Chinese pack, except for the brand names upstream itself never translates.
const zhFlatKeys: Set<string> = flatKeys(zhMessages);
const missingInZh: string[] = [];
upstreamFlat.forEach((key: string) => {
  if (!zhFlatKeys.has(key)) {
    missingInZh.push(key);
  }
});
missingInZh.sort();
const UPSTREAM_BRAND_KEYS: string[] = ['searchEngine.duckduckgo', 'searchEngine.google'];
check('Chinese covers every English key except the upstream brand names',
  missingInZh.length === UPSTREAM_BRAND_KEYS.length
  && missingInZh.every(k => UPSTREAM_BRAND_KEYS.indexOf(k) >= 0),
  missingInZh.join(', '));

// The literal scan above only sees `I18n.get('key')`. A key can also be produced
// by a helper and translated at the call site (`return 'app.noContent'`), which
// that scan misses entirely. This walks every quoted dotted literal in the
// shipped sources, keeps the ones whose first segment is a real catalogue root,
// and requires each to resolve in *both* bundled languages.
const catalogueRoots = new Set<string>();
for (const key of upstreamFlat) {
  catalogueRoots.add(key.split('.')[0]);
}
for (const key of enBuiltin) {
  catalogueRoots.add(key.split('.')[0]);
}
const zhBuiltinSet = new Set<string>(zhBuiltin);
const zhResolves = (key: string): boolean =>
  zhFlatKeys.has(key) || zhBuiltinSet.has(key);
const enBuiltinSet = new Set<string>(enBuiltin);
const enResolves = (key: string): boolean =>
  upstreamFlat.has(key) || enBuiltinSet.has(key);

const unresolvedBilingual: string[] = [];
const dottedLiteral = /'([a-z][A-Za-z0-9]*\.[A-Za-z0-9.]+)'/g;
for (const file of etsFiles(etsRoot)) {
  const text: string = fs.readFileSync(file, 'utf8');
  let match = dottedLiteral.exec(text);
  while (match !== null) {
    const key: string = match[1];
    if (catalogueRoots.has(key.split('.')[0])
      && UPSTREAM_BRAND_KEYS.indexOf(key) < 0) {
      if (!enResolves(key) || !zhResolves(key)) {
        unresolvedBilingual.push(key + ' @ ' + file.slice(file.lastIndexOf('/') + 1)
          + ' en=' + enResolves(key) + ' zh=' + zhResolves(key));
      }
    }
    match = dottedLiteral.exec(text);
  }
}
check('every key literal in the sources resolves in both bundled languages',
  unresolvedBilingual.length === 0, unresolvedBilingual.join('  |  '));

check('the port invents fewer strings than before',
  upstreamFlat.size > 0 && I18n.get('time.hour', new Map<string, string | number>([['h', 4]])) === '4 hours',
  I18n.get('time.hour', new Map<string, string | number>([['h', 4]])));
// The rule action labels come from the original's `actionKeyMap`, so they must
// be the original's own words rather than the port's shorter phrasing.
check('the rule action labels are the original wording',
  I18n.get('article.notify').length > I18n.get('article.star').length,
  I18n.get('article.notify'));

// --- Upstream key roles -------------------------------------------------------
// Resolving is not the same as being used the way the original uses a string.
// Reading `src/components/settings/groups.tsx` showed the group panel had three
// strings in the wrong place — `groups.editName` as a title (it is the rename
// button), `groups.chooseGroup` as a caption (it is a dropdown placeholder) and
// `groups.addToGroup` in the group panel (it belongs to the *source*-side flow).
// A "does it resolve" assertion cannot see any of that, so the roles are pinned.
section('Upstream key roles');

/** The ArkUI sink a key literal sits in, e.g. `Button(` or `.value(`. */
function sinkOf(source: string, key: string): string {
  const at: number = source.indexOf("I18n.get('" + key + "'");
  if (at < 0) {
    return '';
  }
  const before: string = source.slice(0, at);
  const sinks: string[] = ['Text(', 'Button(', 'Select(', '.value('];
  let best: string = '';
  let bestAt: number = -1;
  for (const sink of sinks) {
    const found: number = before.lastIndexOf(sink);
    if (found > bestAt) {
      bestAt = found;
      best = sink;
    }
  }
  return best;
}

const groupPanel: string = fs.readFileSync(etsRoot + '/components/GroupSettingsDialog.ets', 'utf8');
const feedPanel: string = fs.readFileSync(etsRoot + '/components/FeedSettingsDialog.ets', 'utf8');

check('groups.chooseGroup is a dropdown placeholder',
  sinkOf(feedPanel, 'groups.chooseGroup') === '.value(',
  sinkOf(feedPanel, 'groups.chooseGroup'));
check('groups.addToGroup labels a button',
  sinkOf(feedPanel, 'groups.addToGroup') === 'Button(',
  sinkOf(feedPanel, 'groups.addToGroup'));
check('the source-side group flow is not duplicated in the group panel',
  groupPanel.indexOf("I18n.get('groups.chooseGroup')") < 0
  && groupPanel.indexOf("I18n.get('groups.addToGroup')") < 0);
check('groups.deleteSource labels the remove button',
  sinkOf(groupPanel, 'groups.deleteSource') === 'Button(',
  sinkOf(groupPanel, 'groups.deleteSource'));
check('groups.editName is the rename button, not a panel title',
  sinkOf(groupPanel, 'groups.editName') === 'Button(',
  sinkOf(groupPanel, 'groups.editName'));
check('the group panel title is the upstream selected-group label',
  groupPanel.indexOf('I18n.get(this.titleKey())') >= 0
  && groupPanel.indexOf("'groups.selectedSource'") >= 0
  && groupPanel.indexOf("'groups.selectedGroup'") >= 0);
// `groups.sourceHint` promises drag-to-reorder. Dragging is not wired inside the
// group dialog (reordering lives on the sidebar), so rendering the hint there
// would advertise an affordance that is not present.
check('groups.sourceHint is not shown where dragging is unavailable',
  groupPanel.indexOf("I18n.get('groups.sourceHint')") < 0
  && feedPanel.indexOf("I18n.get('groups.sourceHint')") < 0);

// Same audit for the rule editor and the service pane. `rules.selectSource` is
// the *placeholder* of the source dropdown upstream, and the service picker's
// last entry is not a service at all — it opens the issue tracker.
const rulesPanel: string = fs.readFileSync(etsRoot + '/components/RulesDialog.ets', 'utf8');
const servicePanel: string = fs.readFileSync(etsRoot + '/components/ServiceSettingsDialog.ets', 'utf8');

check('rules.selectSource is a dropdown placeholder, not a caption',
  sinkOf(rulesPanel, 'rules.selectSource') === '.value('
  && rulesPanel.indexOf("Text(I18n.get('rules.selectSource'))") < 0,
  sinkOf(rulesPanel, 'rules.selectSource'));
// A placeholder that can never be shown is not a placeholder. The editor must
// start with no source chosen, and the page must not quietly substitute the
// first feed for it.
const indexPage: string = fs.readFileSync(etsRoot + '/pages/Index.ets', 'utf8');
check('the rule editor can actually reach the "select a source" state',
  rulesPanel.indexOf('feedIndex: number = -1') >= 0
  && indexPage.indexOf('initial = this.store.feeds[0].id') < 0);
check('the "no subscriptions" state no longer tells you to select one',
  rulesPanel.indexOf("Text(I18n.get('app.noSubscriptions'))") >= 0);
// Upstream's `serviceOptions()` ends with a `service.suggest` entry that opens
// its issue tracker instead of selecting a service. This port deliberately does
// not offer it (user request): a HarmonyOS build must not funnel reports into an
// Electron project's tracker. The picker must therefore hold exactly the seven
// real choices, and the intro block's wiki link must still work — `onOpenUrl`
// is shared, so deleting the suggest entry must not take the help link with it.
check('the service picker offers exactly the seven real services',
  servicePanel.indexOf("{ value: I18n.get('service.suggest') }") < 0
  && servicePanel.indexOf('SERVICE_SUGGEST_INDEX') < 0
  && servicePanel.indexOf('SERVICE_REQUEST_URL') < 0
  && servicePanel.indexOf('github.com/yang991178/fluent-reader/issues/23') < 0);
check('the picker array itself has seven entries and no suggest label',
  (() => {
    const open: number = servicePanel.indexOf('Select([');
    const close: number = servicePanel.indexOf('])', open);
    if (open < 0 || close < 0) return false;
    const body: string = servicePanel.slice(open, close);
    const entries: number = (body.match(/\{ value: /g) ?? []).length;
    return entries === 7 && body.indexOf('suggest') < 0;
  })());
check('the intro block still links to the upstream wiki',
  servicePanel.indexOf("I18n.get('service.intro')") >= 0
  && servicePanel.indexOf("I18n.get('rules.help')") >= 0
  && servicePanel.indexOf('this.onOpenUrl(SERVICE_HELP_URL)') >= 0);
check('the removed suggest string left both locale packs',
  enMessages['service'] !== undefined
  && (enMessages['service'] as Record<string, Object>)['suggest'] === undefined
  && (zhMessages['service'] as Record<string, Object>)['suggest'] === undefined);

// --- Fetch progress bar --------------------------------------------------------
// Upstream draws `<ProgressBar value={fetchingProgress / fetchingTotal}>` pinned
// to the top of the window whenever it is fetching. The port had no such bar and
// only a write-only `fetchProgress` string, so the ratio is pinned here.
section('Fetch progress bar');
const appStoreSrc: string = fs.readFileSync(etsRoot + '/state/AppStore.ets', 'utf8');
check('the fetch callback records done/total for the bar',
  appStoreSrc.indexOf('this.fetchDone = done;') >= 0
  && appStoreSrc.indexOf('this.fetchTotal = total;') >= 0);
check('the bar is driven by that ratio',
  indexPage.indexOf('value: this.store.fetchDone') >= 0
  && indexPage.indexOf('total: this.store.fetchTotal') >= 0
  && indexPage.indexOf('ProgressType.Linear') >= 0);
// `ProgressOptions.value` is required at this API level, so an indeterminate bar
// is not expressible; drawing it with a total of 0 would show a lie (0%) for the
// whole service-sync phase instead of "unknown".
check('the bar is only drawn once a real total exists',
  indexPage.indexOf('this.store.isFetching && this.store.fetchTotal > 0') >= 0);
check('the write-only progress string is gone',
  appStoreSrc.indexOf('fetchProgress') < 0);

// --- Auto-fetch scheduling -----------------------------------------------------
// Upstream's `fetchItems` picks its source list with
//     last > timenow || last + (s.fetchFrequency || 0) * 60000 <= timenow
// and its `setupAutoFetch` arms a one-shot timeout that refuses to run while
// the settings panel is open. The port had drifted on both counts: it treated
// the frequency field as background-only (a live manual refresh overrode it,
// which upstream never does) and used a repeating interval with no panel guard.
section('Auto-fetch scheduling');
const nowMs: number = 1700000000000;
const minute: number = 60000;
check('an unlimited source (frequency 0) is always due',
  FetchSchedule.due(0, nowMs - 60 * minute, nowMs) === true);
check('a source that has never been fetched is due',
  FetchSchedule.due(720, 0, nowMs) === true
  && FetchSchedule.due(0, 0, nowMs) === true);
check('a source inside its limit is skipped',
  FetchSchedule.due(30, nowMs - 10 * minute, nowMs) === false);
check('a source exactly at its limit is due, matching `<=` upstream',
  FetchSchedule.due(30, nowMs - 30 * minute, nowMs) === true);
check('a source past its limit is due',
  FetchSchedule.due(30, nowMs - 31 * minute, nowMs) === true);
check('the limit counts minutes, not seconds',
  FetchSchedule.due(1, nowMs - 59000, nowMs) === false
  && FetchSchedule.due(1, nowMs - 61000, nowMs) === true);
// The clock moving backwards leaves `lastFetched` in the future; upstream's
// `last > timenow` disjunct keeps fetching instead of stalling for a whole
// interval, which a plain `elapsed >= frequency` test would not.
check('a lastFetched in the future is still due',
  FetchSchedule.due(720, now + minute, nowMs) === true);
check('a non-positive frequency cannot block a fetch',
  FetchSchedule.due(-5, now - 1000, nowMs) === true);

check('the limit applies to an unscoped refresh',
  FetchSchedule.appliesToScope(null) === true);
check('a scoped refresh bypasses the limit',
  FetchSchedule.appliesToScope([3]) === false
  && FetchSchedule.appliesToScope([]) === false);
check('the store gates the frequency on the scope, not on `background`',
  appStoreSrc.indexOf('FetchSchedule.appliesToScope(scopeIds), scopeIds)') >= 0
  && appStoreSrc.indexOf('scopeIds === null ? background : false') < 0);
check('the fetch loop consults FetchSchedule for every source',
  fs.readFileSync(etsRoot + '/services/FeedService.ets', 'utf8')
    .indexOf('!applyFrequency || FetchSchedule.due(feeds[i].fetchFrequency,') >= 0);
check('the old background-only rule is gone',
  fs.readFileSync(etsRoot + '/services/FeedService.ets', 'utf8')
    .indexOf('respectFrequency') < 0
  && appStoreSrc.indexOf('respectFrequency') < 0);
check('the timer is one-shot and re-arms, instead of a repeating interval',
  indexPage.indexOf('this.refreshTimer = setTimeout(async () => {') >= 0
  && indexPage.indexOf('this.armRefreshTimer(this.store.settings.fetchIntervalMinutes);') >= 0
  && indexPage.indexOf('setInterval(') < 0);
check('a tick that lands while the settings panel is open retries in a minute',
  indexPage.indexOf('if (this.settingsOpen) {') >= 0
  && indexPage.indexOf('this.armRefreshTimer(1);') >= 0);
check('an in-flight fetch is not started twice',
  indexPage.indexOf('if (!this.store.isFetching) {') >= 0);
check('the panel-open flag is cleared on every close path',
  fs.readFileSync(etsRoot + '/components/SettingsDialog.ets', 'utf8')
    .indexOf('this.onClose();') >= 0
  && indexPage.indexOf('onClose: () => {') >= 0
  && indexPage.indexOf('this.settingsOpen = false;') >= 0);
check('the timer is released when the page goes away',
  indexPage.indexOf('clearTimeout(this.refreshTimer);') >= 0);

// The two scheduling dropdowns are different lists upstream, and the port had
// them swapped: `settings/app.tsx` offers Never/10/15/20/30/45 minutes/1 hour
// for the automatic interval, while `settings/sources.tsx` offers
// Unlimited/15/30/1h/2h/3h/6h/12h per source. The port used the (mangled)
// source list for both.
const settingsPanel: string = fs.readFileSync(etsRoot + '/components/SettingsDialog.ets', 'utf8');
check('the automatic interval options are the original seven',
  FetchSchedule.INTERVALS.join(',') === '0,10,15,20,30,45,60');
check('the per-source frequency options are the original eight',
  FetchSchedule.FREQUENCIES.join(',') === '0,15,30,60,120,180,360,720');
check('interval 0 is labelled "never"',
  settingsPanel.indexOf("I18n.get('app.never')") >= 0);
check('a stored value outside the original list stays selectable',
  FetchSchedule.options(FetchSchedule.INTERVALS, 240).join(',') === '0,10,15,20,30,45,60,240'
  && FetchSchedule.options(FetchSchedule.FREQUENCIES, 15).length === 8);
check('both dropdowns render and index the same list',
  settingsPanel.indexOf('this.intervalValues()[index]') >= 0
  && settingsPanel.indexOf('this.intervalValues().indexOf(this.fetchInterval)') >= 0);
check('the source panel takes its options from FetchSchedule too',
  feedPanel.indexOf('FetchSchedule.options(FetchSchedule.FREQUENCIES, this.fetchFrequency)') >= 0
  && feedPanel.indexOf('this.frequencyValues()[index]') >= 0);

// A refresh must not rewrite a source's name. Upstream fills the name once,
// when it is empty (`fetchMetaData`), and `fetchItems` never touches it; the
// port overwrote title/link/description on every fetch, which reverted renames
// and flattened every OPML-imported title back to the feed's own <title>
// (measured on device: three rows all reading "Local Full Text").
const feedServiceSrc: string = fs.readFileSync(etsRoot + '/services/FeedService.ets', 'utf8');
check('a refresh only fills metadata that is still missing',
  feedServiceSrc.indexOf('if (feed.title.length === 0 && parsed.feed.title) {') >= 0
  && feedServiceSrc.indexOf('if (feed.link.length === 0 && parsed.feed.link) {') >= 0
  && feedServiceSrc.indexOf('if (feed.description.length === 0 && parsed.feed.description) {') >= 0
  && feedServiceSrc.indexOf('feed.title = parsed.feed.title;') >= 0);
check('the unconditional overwrite is gone',
  feedServiceSrc.indexOf('if (parsed.feed.title) {\n      feed.title = parsed.feed.title;') < 0);

// --- System notifications ------------------------------------------------------
// The original raises `new Notification(...)` per rule-notified article and
// hangs `onclick` off it. Two of those three parts had never existed here:
// consent (HarmonyOS refuses `publish` with 1600004 until the user enables
// notifications, and the failure was swallowed into an invisible console.warn)
// and click-through (no wantAgent, so a tap did nothing).
section('System notifications');
const notifierSrc: string = fs.readFileSync(etsRoot + '/utils/Notifier.ets', 'utf8');
const deepLinkSrc: string = fs.readFileSync(etsRoot + '/utils/DeepLink.ets', 'utf8');
const abilitySrc: string = fs.readFileSync(etsRoot + '/entryability/EntryAbility.ets', 'utf8');
check('the app asks for notification consent, checking first and not on every publish',
  notifierSrc.indexOf('notificationManager.isNotificationEnabledSync()') >= 0
  && notifierSrc.indexOf('await notificationManager.requestEnableNotification(context)') >= 0
  && indexPage.indexOf('await Notifier.ensureEnabled(this.hostContext())') >= 0);
// The field has to be *absent* when there is no agent: passing an explicit
// `undefined` counts as a present, non-object value and `publish` rejects the
// whole request with `401 Invalid parameter ... wantAgent must be object`
// (measured on device — the notification then never appears).
check('the notification carries a click-through agent with the article id',
  notifierSrc.indexOf('wantAgent.OperationType.START_ABILITY') >= 0
  && notifierSrc.indexOf("'articleId': articleId.toString()") >= 0
  && notifierSrc.indexOf('if (agent !== undefined) {') >= 0
  && notifierSrc.indexOf('request.wantAgent = agent;') >= 0
  && notifierSrc.indexOf('wantAgent: agent') < 0);
check('tapping the notification dismisses it, like the original popup',
  notifierSrc.indexOf('tapDismissed: true') >= 0);
check('both launch paths read the article id out of the want',
  abilitySrc.indexOf('onCreate(want: Want, launchParam: AbilityConstant.LaunchParam)') >= 0
  && abilitySrc.indexOf('onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam)') >= 0
  && abilitySrc.indexOf("parameters['articleId']") >= 0
  && abilitySrc.indexOf('DeepLink.publish(articleId)') >= 0);
// A `@StorageLink` only reacts to a *changed* value (README ㉖), so tapping the
// same notification twice has to look different to the binding.
check('every deep link is a fresh token, and consuming clears it',
  deepLinkSrc.indexOf('DeepLink.sequence++') >= 0
  && deepLinkSrc.indexOf('DeepLink.sequence.toString() + \':\' + articleId.toString()') >= 0
  && deepLinkSrc.indexOf("AppStorage.setOrCreate(DeepLink.STORAGE_KEY, '')") >= 0);
check('the page binds the same AppStorage key DeepLink publishes to',
  deepLinkSrc.indexOf("static readonly STORAGE_KEY: string = 'sheafReaderPendingArticle'") >= 0
  && indexPage.indexOf("@StorageLink('sheafReaderPendingArticle')") >= 0);
check('a cold start and a warm tap both open the article',
  indexPage.indexOf('onPendingArticleChange(): void {') >= 0
  && indexPage.indexOf('onPageShow(): void {') >= 0
  && indexPage.indexOf('this.openPendingArticle();') >= 0
  && indexPage.indexOf('this.store.openArticleById(articleId);') >= 0);
check('the notification is suppressed while the window is focused, as upstream does',
  appStoreSrc.indexOf('background && !this.windowFocused') >= 0
  && appStoreSrc.indexOf('windowFocused: boolean = true') >= 0);
check('window focus comes from the window event, not a guess',
  indexPage.indexOf("host.on('windowEvent'") >= 0
  && indexPage.indexOf('window.WindowEventType.WINDOW_ACTIVE') >= 0
  && indexPage.indexOf('window.WindowEventType.WINDOW_INACTIVE') >= 0
  // A minimized (hidden) window is not focused either; measured on the
  // emulator, a Home press delivers nothing at all.
  && indexPage.indexOf('window.WindowEventType.WINDOW_HIDDEN') >= 0
  // WINDOW_SHOWN must not re-open the gate: on device it arrives *between*
  // ACTIVE and INACTIVE, so treating it as focus suppressed the notification.
  && indexPage.indexOf('=== window.WindowEventType.WINDOW_SHOWN') < 0);
check('a refused notification is reported instead of silently swallowed',
  appStoreSrc.indexOf("I18n.get('app.notifyFailed')") >= 0
  && appStoreSrc.indexOf('Notifier.lastError') >= 0
  && notifierSrc.indexOf('Notifier.lastError = error.code') >= 0);
// The refusal message is a port-specific string (the original cannot fail), so
// it lives in the built-in catalogues rather than upstream's packs.
I18n.useMessages('en-US', enMessages, enMessages);
const enNotifyFailure: string = I18n.get('app.notifyFailed');
I18n.useMessages('zh-CN', zhMessages, enMessages);
const zhNotifyFailure: string = I18n.get('app.notifyFailed');
I18n.useMessages('en-US', enMessages, enMessages);
check('the refusal message is translated in both bundled languages',
  enNotifyFailure.length > 0 && zhNotifyFailure.length > 0
  && enNotifyFailure !== 'app.notifyFailed' && zhNotifyFailure !== 'app.notifyFailed'
  && enNotifyFailure !== zhNotifyFailure);


// --- Reader body blocks --------------------------------------------------------
// Upstream renders the article HTML in a webview, so inline images appear with
// the text. The port drew a single `Text` run and the extractor deleted `<img>`
// outright, which silently dropped every picture in every article.
section('Reader body blocks');
const readerPage: string = fs.readFileSync(etsRoot + '/components/ArticleReaderView.ets', 'utf8');
const kindsOf = (blocks: ReaderBlock[]): string =>
  blocks.map(b => b.kind === ReaderBody.IMAGE ? 'I'
    : (b.kind === ReaderBody.VIDEO ? 'V' : 'T')).join('');
const base = 'https://blog.example.com/posts/2024/hello.html';

const mixed = ReaderBody.blocks(
  '<p>First paragraph.</p><img src="/media/chart.png"><p>Second paragraph.</p>', base);
check('an image between two paragraphs becomes its own block, in order',
  kindsOf(mixed) === 'TIT'
  && mixed[0].value === 'First paragraph.'
  && mixed[2].value === 'Second paragraph.');
check('a root-relative image src is resolved against the article URL',
  mixed[1].value === 'https://blog.example.com/media/chart.png', mixed[1].value);
check('a path-relative image src is resolved against the article directory',
  ReaderBody.blocks('<img src="chart.png">', base)[0].value
    === 'https://blog.example.com/posts/2024/chart.png');
check('a protocol-relative image src gains the scheme',
  ReaderBody.blocks('<img src="//cdn.example.com/a.png">', base)[0].value
    === 'https://cdn.example.com/a.png');
check('an absolute image src is left alone',
  ReaderBody.blocks('<img src="http://x.test/a.png">', base)[0].value
    === 'http://x.test/a.png');
check('a base64 image is kept as-is, without a base URL',
  ReaderBody.blocks('<img src="data:image/png;base64,AAAA">', '')[0].value
    === 'data:image/png;base64,AAAA');
check('an image with no usable src is dropped rather than drawn as a broken box',
  kindsOf(ReaderBody.blocks('<p>Prose here.</p><img alt="x"><img src="">', base)) === 'T'
  && kindsOf(ReaderBody.blocks('<img src="/chart.png">', '')) === '');
check('images are dropped from the plain-text view',
  ReaderBody.text('<p>First.</p><img src="/a.png"><p>Second.</p>')
    === 'First.\n\nSecond.');
// Feeds deliver escaped markup (sspai style); it has to be decoded before the
// body can be split, or the image stays invisible as literal text.
check('entity-escaped markup still yields an image block',
  kindsOf(ReaderBody.blocks(
    '&lt;p&gt;Text.&lt;/p&gt;&lt;img src=&quot;/a.png&quot;&gt;', base)) === 'TI'
  && ReaderBody.blocks('&lt;img src=&quot;/a.png&quot;&gt;', base)[0].value
    === 'https://blog.example.com/a.png');
check('a list item keeps its bullet',
  ReaderBody.blocks('<ul><li>One</li><li>Two</li></ul>', base)
    .every(b => b.value.startsWith('\u2022 ')));
check('a line break separates two paragraphs',
  kindsOf(ReaderBody.blocks('one<br>two', base)) === 'TT');
check('script and style contents never reach a block',
  ReaderBody.blocks('<p>Keep.</p><script>var a = 1;</script><style>p{}</style>', base)
    .every(b => b.value.indexOf('var a') < 0 && b.value.indexOf('p{}') < 0));
check('an empty body yields no blocks',
  ReaderBody.blocks('', base).length === 0
  && ReaderBody.text('').length === 0);

// Inline video. Feeds that publish video items often ship nothing but a
// `<video>` element, so those articles rendered as a title with a blank body.
const VIDEO_BODY = '<p>Before.</p><video src="/v/clip.mp4" poster="/v/frame.jpg" controls>'
  + '</video><p>After.</p>';
const videoBlocks = ReaderBody.blocks(VIDEO_BODY, base);
check('a video between two paragraphs becomes its own block, in order',
  kindsOf(videoBlocks) === 'TVT' && videoBlocks[1].value === 'https://blog.example.com/v/clip.mp4');
check('the video block carries its resolved poster frame',
  videoBlocks[1].poster === 'https://blog.example.com/v/frame.jpg');
check('a video whose file sits in a nested <source> is still found',
  kindsOf(ReaderBody.blocks('<video poster="/p.jpg">'
    + '<source src="/v/a.mp4" type="video/mp4"></video>', base)) === 'V'
  && ReaderBody.blocks('<video><source src="/v/a.mp4"></video>', base)[0].value
    === 'https://blog.example.com/v/a.mp4');
check('a video with no usable source is dropped rather than drawn as an empty player',
  kindsOf(ReaderBody.blocks('<p>Prose.</p><video controls></video>', base)) === 'T'
  && kindsOf(ReaderBody.blocks('<video src="/v/a.mp4"></video>', '')) === '');
check('a poster-less video leaves the poster empty instead of a broken image',
  ReaderBody.blocks('<video src="https://cdn.test/a.mp4"></video>', base)[0].poster === ''
  && ReaderBody.blocks('<video src="https://cdn.test/a.mp4"></video>', base)[0].value
    === 'https://cdn.test/a.mp4');
check('a relative video src is resolved against the article URL',
  ReaderBody.blocks('<video src="clip.mp4"></video>', base)[0].value
    === 'https://blog.example.com/posts/2024/clip.mp4');
check('a self-closing video tag is recognised',
  kindsOf(ReaderBody.blocks('<video src="/v/a.mp4"/>', base)) === 'V');
check('entity-escaped video markup still yields a video block',
  kindsOf(ReaderBody.blocks('&lt;video src=&quot;/v/a.mp4&quot;&gt;&lt;/video&gt;', base)) === 'V');
check('videos are dropped from the plain-text view',
  ReaderBody.text('<p>First.</p><video src="/v/a.mp4"></video><p>Second.</p>')
    === 'First.\n\nSecond.');
check('image and video blocks keep their relative order',
  kindsOf(ReaderBody.blocks(
    '<img src="/a.png"><video src="/v/a.mp4"></video><img src="/b.png">', base)) === 'IVI');

// The extractor has to carry the image out of a fetched page, which is where
// "load full content" gets its body from.
const pageWithImage = '<html><body><article>'
  + '<p>' + 'Prose that is comfortably long enough to be scored as body copy. '.repeat(4) + '</p>'
  + '<figure><img src="/assets/diagram.png"></figure>'
  + '<p>' + 'More prose follows the picture so the body clears the minimum. '.repeat(4) + '</p>'
  + '</article></body></html>';
const extractedWithImage = ContentExtractor.extract(pageWithImage, 'https://site.test/a/b.html');
check('full-content extraction keeps the image with an absolute URL',
  extractedWithImage !== null
  && extractedWithImage.html.indexOf('<img src="https://site.test/assets/diagram.png">') >= 0,
  extractedWithImage === null ? 'extraction failed' : extractedWithImage.html.slice(0, 80));
check('an image-only figure survives even though it has no prose',
  ContentExtractor.extract('<html><body><article><figure><img src="https://site.test/x.png">'
    + '</figure><p>' + 'A body paragraph long enough to pass the total length gate. '.repeat(6)
    + '</p></article></body></html>', 'https://site.test/') !== null);
check('an image with no src cannot rescue a fragment',
  (() => {
    const stripped = ContentExtractor.extract('<html><body><article><figure><img alt="x"></figure>'
      + '<p>' + 'A body paragraph long enough to pass the total length gate. '.repeat(6)
      + '</p></article></body></html>', 'https://site.test/');
    return stripped !== null && stripped.html.indexOf('<img') < 0;
  })());

// View wiring: the reader has to draw the blocks, not one text run.
check('the reader renders body blocks instead of a single text run',
  readerPage.indexOf('ForEach(this.bodyBlocks(), (block: ReaderBlock, index: number) => {') >= 0
  && readerPage.indexOf('if (block.kind === ReaderBody.IMAGE) {') >= 0
  && readerPage.indexOf('Image(block.value)') >= 0
  && readerPage.indexOf('Text(block.value)') >= 0);
check('relative images are resolved against the article link',
  readerPage.indexOf('ReaderBody.blocks(this.bodyHtml(), this.article.link)') >= 0);
check('the reader draws a Video for video blocks, with the poster as placeholder',
  readerPage.indexOf('} else if (block.kind === ReaderBody.VIDEO) {') >= 0
  && readerPage.indexOf('Video({ src: block.value, previewUri: block.poster })') >= 0
  && readerPage.indexOf('Video({ src: block.value })') >= 0
  && readerPage.indexOf('.controls(true)') >= 0);
// Selected-text search. ArkUI measures a `TextRange` against the very `Text`
// the menu was opened on, so the clicked range has to be sliced from *that*
// block. The first revision sliced the whole plain-text body instead: the
// offsets then landed near the top of the article, and the engine was asked to
// search for whatever happened to sit there — a different word than the one
// under the finger, which is exactly what was reported.
check('the selection menu slices the block it was opened on',
  readerPage.indexOf('this.handleSelectionMenu(menuItem, range, block.value)') >= 0
  && readerPage.indexOf('this.selectionText = block.value.substring(start, end).trim();') >= 0);
check('the clicked range is sliced from that block, not from the whole body',
  readerPage.indexOf('SearchEngines.selectionOf(blockText, start, end)') >= 0
  && readerPage.indexOf('readableBody') < 0);
const SEL_HTML: string = '<p>alpha beta</p><p>gamma delta</p><p>epsilon zeta</p>';
const selBlocks: ReaderBlock[] = ReaderBody.blocks(SEL_HTML, '');
const selWord: string = selBlocks[2].value;
const selAt: number = selWord.indexOf('zeta');
check('a range in the third paragraph slices that paragraph',
  selBlocks.length === 3 && selAt >= 0
  && SearchEngines.selectionOf(selBlocks[2].value, selAt, selAt + 4) === 'zeta',
  JSON.stringify([selBlocks.length, selWord, selAt]));
// The old path, for contrast: the same offsets on the whole body hit a
// different word, so the bug is reproducible from the model alone.
check('the same offsets on the whole body would have searched other text',
  SearchEngines.selectionOf(ReaderBody.text(SEL_HTML), selAt, selAt + 4) !== 'zeta',
  JSON.stringify(SearchEngines.selectionOf(ReaderBody.text(SEL_HTML), selAt, selAt + 4)));

// --- Drawer hit-testing --------------------------------------------------------
// `HitTestMode.None` on the overlay *wrapper* does not disable its subtree: a
// child declaring `HitTestMode.Default` still participates. Measured on device,
// the full-size transparent click-catcher stayed the top-most hit target while
// the drawer was closed and swallowed every tap on the page (the hit stack at
// two probe points ended on it). The gate therefore has to sit on the catcher.
section('Drawer hit-testing');
check('the click-catcher is gated on the drawer being open',
  indexPage.indexOf('.hitTestBehavior(this.store.sidebarOpen\n                ? HitTestMode.Default : HitTestMode.None)') >= 0);

// Upstream's refresh button goes disabled while fetching and keeps its icon
// (`disabled={isFetching}` on the `nav.refresh` FlatButton). This port used to
// swap in `ic_close`, i.e. it put a cancel affordance on a button that still
// refreshed when pressed.
const sidebarSrc: string = fs.readFileSync(etsRoot + '/components/SidebarView.ets', 'utf8');
check('the refresh button is disabled while fetching, not relabelled',
  sidebarSrc.indexOf('.enabled(!this.store.isFetching)') >= 0
  && sidebarSrc.indexOf("this.store.isFetching ? $r('app.media.ic_close')") < 0);

// Upstream keeps refresh in its *title bar* (`nav.refresh`), so it is on screen
// regardless of the sidebar. This port had it only in the sidebar header, which
// left no visible refresh control once the drawer was closed.
const listSrc: string = fs.readFileSync(etsRoot + '/components/ArticleListView.ets', 'utf8');
check('the list header carries the always-visible refresh button',
  listSrc.indexOf('onRefresh: () => void') >= 0
  && listSrc.indexOf("$r('app.media.ic_refresh')") >= 0
  && listSrc.indexOf('this.onRefresh();') >= 0
  && listSrc.indexOf('.enabled(!this.store.isFetching)') >= 0);
check('the page wires that button to the same fetch path',
  indexPage.indexOf('onRefresh: async () =>') >= 0
  && indexPage.indexOf('await this.store.refreshFeeds();') >= 0);

// --- Upstream-absent UI removed after the live Miniflux run --------------------
// Three invented things came out of pointing the app at a real Miniflux account.
// (1) A "mark as read on open" switch: upstream has no such setting (`card.tsx`
// marks read unconditionally) and no code here ever consulted it, so it only
// lied. (2) and (3) sidebar Unread / Starred rows: upstream's sidebar is Search,
// All articles, Subscriptions (`menu.tsx`), and those two presets are filter-bar
// toggles instead.
const modelsSrc: string = fs.readFileSync(etsRoot + '/model/Models.ets', 'utf8');
check('the invented "mark as read on open" switch is gone everywhere',
  settingsPanel.indexOf('markReadOnScroll') < 0
  && settingsPanel.indexOf('app.markReadOnOpenHint') < 0
  && modelsSrc.indexOf('markReadOnScroll') < 0
  && appStoreSrc.indexOf('mark_read_scroll') < 0
  && indexPage.indexOf('markReadOnScroll') < 0);
check('the sidebar no longer has the upstream-absent Unread / Starred rows',
  sidebarSrc.indexOf("I18n.get('app.unread')") < 0
  && sidebarSrc.indexOf("I18n.get('app.starred')") < 0
  && sidebarSrc.indexOf('openUnread') < 0
  && sidebarSrc.indexOf('openStarred') < 0
  && sidebarSrc.indexOf('NavType.UNREAD') < 0
  && sidebarSrc.indexOf('NavType.STARRED') < 0);
check('the removed labels left both locales too',
  i18nSource.indexOf("'app.unread'") < 0
  && i18nSource.indexOf("'app.starred'") < 0
  && i18nSource.indexOf('app.markReadOnOpenHint') < 0);

// --- Reader font family: the option was removed --------------------------------
// A `CustomDialogController` builds its content once, so a handler that reads
// `this.fontSize` recomputes from the value captured when the panel opened:
// three taps of "+" in a row all wrote "16 + 1" and the label never moved
// (measured on device). The stepper drives a working copy the panel owns.
check('the font-size stepper reads and writes its own state, not a stale @Prop',
  settingsPanel.indexOf('this.fontSizeShown.toString()') >= 0
  && settingsPanel.indexOf('this.fontSizeShown = this.fontSizeShown + 1;') >= 0
  && settingsPanel.indexOf('this.fontSizeShown = this.fontSizeShown - 1;') >= 0
  && settingsPanel.indexOf('onFontSizeChange(this.fontSize + 1)') < 0
  && settingsPanel.indexOf('onFontSizeChange(this.fontSize - 1)') < 0);
check('the panel seeds that copy from the prop it was opened with',
  settingsPanel.indexOf('this.fontSizeShown = this.fontSize;') >= 0);
// The reader's font *family* picker used to sit next to it, fed by the platform
// enumeration plus a measured fallback list. It was removed on request: the
// reader now always renders in the system font, and the setting, its setter, its
// `font_family` row and the `FontFamily` utility went with it. (Upstream still
// has this setting — recorded as a deliberate deviation in the README.)
// These checks read the page, store and panel sources, which are loaded further
// down in this file, so they live here rather than next to the removed section.
check('the settings panel no longer offers a font picker',
  settingsPanel.indexOf("I18n.get('article.font')") < 0
  && settingsPanel.indexOf('FontFamily') < 0
  && settingsPanel.indexOf('fontFamilyShown') < 0
  && settingsPanel.indexOf("I18n.get('article.fontSize')") >= 0);
check('the reader never sets an explicit font family',
  readerPage.indexOf('.fontFamily(') < 0);
check('the settings model no longer carries a font family',
  ('fontFamily' in new AppSettings()) === false);
check('the store neither loads nor saves a font family',
  appStoreSrc.indexOf('font_family') < 0
  && appStoreSrc.indexOf('setFontFamily') < 0);
check('the font-family utility is gone',
  fs.existsSync(etsRoot + '/utils/FontFamily.ets') === false);
check('the reader subtree is still keyed on the typography it consumes',
  indexPage.indexOf("+ '-' + this.store.settings.fontSize.toString()") >= 0
  && indexPage.indexOf('this.store.settings.lineHeight.toString()') >= 0);

// --- A settings change has to reach the store's observers ----------------------
// `settings` is nested inside the `@Observed` store, so `settings.fontSize = n`
// notifies nobody. Measured on device: the panel read "24 px" while the reader
// still drew 16 px metrics, because the page never re-rendered. Each setter now
// replaces the whole object with a copy, which *is* a property write on the store.
const setA = new AppSettings();
setA.darkMode = DarkModeSetting.DARK;
setA.fetchIntervalMinutes = 45;
setA.fontSize = 22;
setA.lineHeight = 1.9;
setA.showThumbnails = false;
setA.openInBuiltInView = false;
setA.searchEngine = SearchEngine.Bing;
const setB = setA.copy();
check('AppSettings.copy() carries every field over',
  setB.darkMode === DarkModeSetting.DARK && setB.fetchIntervalMinutes === 45
  && setB.fontSize === 22 && setB.lineHeight === 1.9
  && setB.showThumbnails === false
  && setB.openInBuiltInView === false && setB.searchEngine === SearchEngine.Bing);
setB.fontSize = 12;
setB.lineHeight = 1.2;
check('AppSettings.copy() is a real copy, not the same object',
  setB !== setA && setA.fontSize === 22 && setB.fontSize === 12
  && setA.lineHeight === 1.9 && setB.lineHeight === 1.2);
check('every settings setter publishes the change to the store',
  appStoreSrc.indexOf('this.settings = this.settings.copy();') >= 0
  && (() => {
    const setters: string[] = ['setDarkMode', 'setFontSize',
      'setFetchInterval', 'setShowThumbnails', 'setOpenInBuiltInView', 'setSearchEngine'];
    for (const name of setters) {
      const at: number = appStoreSrc.indexOf('async ' + name + '(');
      if (at < 0) {
        return false;
      }
      const end: number = appStoreSrc.indexOf('\n  }', at);
      if (end < 0 || appStoreSrc.slice(at, end).indexOf('this.publishSettings();') < 0) {
        return false;
      }
    }
    return true;
  })());

// --- The narrow list pane must not spill into the reader ------------------------
// The filter labels need more width than a narrow pane can give and the pane is
// `LIST_MIN`..`LIST_MAX` (300–420vp), so as a `Row` they ran past the pane's right
// edge and drew on top of the reader — measured on device, the row was
// `[356,317][761,353]` while the last chip ended at x=916. The same measurement
// showed the header's title Column squeezed to zero width (no title in the dump at
// all): the icon group alone needs ≈296vp. Both rows wrap now, and the header
// stacks below 420vp.
const wrapCount: number = (listSrc.match(/Flex\(\{ wrap: FlexWrap\.Wrap \}\)/g) ?? []).length;
check('both chip rows wrap instead of overflowing the pane',
  wrapCount === 2, 'wrap floors: ' + wrapCount);
check('the filter chips sit in the wrapping container, not a bare Row',
  /Flex\(\{ wrap: FlexWrap\.Wrap \}\) \{\s*ChipView\(\{/.test(listSrc)
  && listSrc.indexOf('Filter toggles. Independent bits on top of the sidebar') >= 0);
check('the list header stacks when the pane cannot hold title and icons',
  listSrc.indexOf('private headerStacks(): boolean {') >= 0
  && listSrc.indexOf('return this.paneWidth < 420;') >= 0
  && listSrc.indexOf('if (this.headerStacks()) {') >= 0
  && listSrc.indexOf('} else {') >= 0);
check('the title and the icon group stay reachable in both header layouts',
  (listSrc.match(/this\.HeaderTitle\(\)/g) ?? []).length === 2
  && (listSrc.match(/this\.HeaderButtons\(\)/g) ?? []).length === 2);
check('wrapped chips get vertical spacing between the lines',
  listSrc.indexOf('.margin({ right: this.gap, bottom: 6 })') >= 0);

// --- Touch targets --------------------------------------------------------------
// The UX guidance requires a tap area of at least 40vp x 40vp. Measured on the
// `Huawei_Tablet` image, 35 of the port's 44 clickable targets were under it, so
// buttons got a `responseRegion` (hit area only — every verified layout stays
// put) and the chips and sidebar rows grew for real.
check('the minimum tap area is the documented 40vp',
  TouchTarget.MIN === 40, String(TouchTarget.MIN));
const r30 = TouchTarget.region(30);
check('a 30vp control gets a 40vp region centred on it',
  r30.width === 40 && r30.height === 40 && r30.x === -5 && r30.y === -5,
  JSON.stringify(r30));
check('an already-large control is not shrunk by the region helper',
  TouchTarget.region(48).width === 40 && TouchTarget.region(48).x === 0,
  JSON.stringify(TouchTarget.region(48)));
const rArrow = TouchTarget.regionFor(24, 30);
check('a non-square control gets per-axis padding',
  rArrow.x === -8 && rArrow.y === -5 && rArrow.width === 40 && rArrow.height === 40,
  JSON.stringify(rArrow));
check('the list header buttons carry a 40vp response region',
  (listSrc.match(/\.responseRegion\(TouchTarget\.region\(30\)\)/g) ?? []).length === 5
  && listSrc.indexOf('.responseRegion(TouchTarget.region(26))') >= 0
  && listSrc.indexOf('.responseRegion(TouchTarget.regionFor(24, 30))') >= 0,
  'header regions: ' + (listSrc.match(/responseRegion/g) ?? []).length);
check('the reader toolbar buttons carry a 40vp response region',
  (readerPage.match(/\.responseRegion\(TouchTarget\.region\(34\)\)/g) ?? []).length === 5,
  'reader regions: ' + (readerPage.match(/responseRegion/g) ?? []).length);
check('the sidebar rows and footer buttons reach the minimum',
  sidebarSrc.indexOf('.constraintSize({ minHeight: TouchTarget.MIN })') >= 0
  && (sidebarSrc.match(/\.constraintSize\(\{ minHeight: TouchTarget\.MIN \}\)/g) ?? []).length === 7
  && (sidebarSrc.match(/\.responseRegion\(TouchTarget\.region\(34\)\)/g) ?? []).length === 3,
  'sidebar rows: ' + (sidebarSrc.match(/minHeight: TouchTarget\.MIN/g) ?? []).length);
check('the filter chips are tall enough to tap',
  listSrc.indexOf('.padding({ left: 12, right: 12, top: 13, bottom: 13 })') >= 0
  && listSrc.indexOf('.fontSize(12)') >= 0);
// The dialogs' own round buttons and the article cards were the last targets
// under the minimum; they carry a region too now, so nothing interactive is left
// below 40vp.
const regionFiles: string[] = ['AddFeedDialog.ets', 'ArticleCards.ets', 'FeedSettingsDialog.ets',
  'GroupSettingsDialog.ets', 'LogMenuView.ets', 'RulesDialog.ets',
  'ServiceSettingsDialog.ets', 'SettingsDialog.ets'];
const noRegion: string[] = [];
for (const name of regionFiles) {
  const text: string = fs.readFileSync(etsRoot + '/components/' + name, 'utf8');
  if (text.indexOf('responseRegion(TouchTarget.region(') < 0
    || text.indexOf("from '../utils/TouchTarget'") < 0) {
    noRegion.push(name);
  }
}
check('every dialog with a round icon button enlarges its target',
  noRegion.length === 0, noRegion.join(', '));
// A region belongs to the *clickable* component. Putting one on the 12vp icon
// inside a button creates a hit area that is not the button — which is exactly
// what a first pass did, so it is pinned here.
const smallRegions: string[] = [];
for (const file of etsFiles(etsRoot)) {
  const text: string = fs.readFileSync(file, 'utf8');
  const re = /responseRegion\(TouchTarget\.region\((\d+)\)\)/g;
  let m = re.exec(text);
  while (m !== null) {
    if (Number(m[1]) < 20) {
      smallRegions.push(file.slice(file.lastIndexOf('/') + 1) + ': ' + m[1]);
    }
    m = re.exec(text);
  }
}
check('no response region is sized for a decorative icon',
  smallRegions.length === 0, smallRegions.join(', '));

// --- The filter row's contents --------------------------------------------------
// Three search modifiers used to be chips here and were removed on request: they
// modify *search*, not the list, so the row keeps the two presets and
// "show hidden". The ▾ menu still reaches the first two; the author scope was
// removed from the list filter altogether, and survives only for rules.
check('the filter row no longer offers the three search modifiers',
  listSrc.indexOf("label: I18n.get('context.fullSearch')") < 0
  && listSrc.indexOf("label: I18n.get('context.caseSensitive')") < 0
  && listSrc.indexOf("label: I18n.get('rules.creator')") < 0);
check('the filter row still offers the presets and show-hidden',
  listSrc.indexOf("label: I18n.get('context.unreadOnly')") >= 0
  && listSrc.indexOf("label: I18n.get('context.starredOnly')") >= 0
  && listSrc.indexOf("label: I18n.get('context.showHidden')") >= 0);
check('the ▾ menu still reaches the two search modifiers',
  listSrc.indexOf("MenuItem({ content: I18n.get('context.caseSensitive') })") >= 0
  && listSrc.indexOf("MenuItem({ content: I18n.get('context.fullSearch') })") >= 0);
// The list filter's creator scope was deleted outright on request. What is left
// is FullSearch and CaseInsensitive, plus the rule-only creator bit, which has
// to keep its upstream value (1 << 5) or stored rules change meaning.
const filterSrc: string = fs.readFileSync(etsRoot + '/model/Filter.ets', 'utf8');
const filterEnumAt: number = filterSrc.indexOf('export enum FilterType');
const filterEnum: string = filterSrc.slice(filterEnumAt, filterSrc.indexOf('}', filterEnumAt));
check('the FilterType enum no longer declares a creator bit',
  filterEnum.length > 0 && filterEnum.indexOf('Creator') < 0
  && (FilterType as unknown as Record<string, number>)['CreatorSearch'] === undefined,
  filterEnum.replace(/\s+/g, ' '));
check('the rule creator scope keeps the upstream bit and the shared full-text bit',
  RuleSearchScope.Creator === 1 << 5
  && (RuleSearchScope.FullSearch as number) === (FilterType.FullSearch as number)
  && RuleSearchScope.Title === 0);
check('the list filter keeps the two modifiers that are still reachable',
  FilterType.FullSearch !== undefined && FilterType.CaseInsensitive !== undefined);
check('the dead creator filter entry point is gone from the store',
  appStoreSrc.indexOf('setCreatorSearch') < 0
  && appStoreSrc.indexOf('FilterType.CreatorSearch') < 0);
check('the rules panel still offers the author scope',
  rulesPanel.indexOf('RuleSearchScope.Creator') >= 0
  && rulesPanel.indexOf("I18n.get('rules.creator')") >= 0);

console.log('\n========================================');
console.log('  passed: ' + passed + '   failed: ' + failed);
console.log('========================================');
if (failed > 0) {
  process.exit(1);
}