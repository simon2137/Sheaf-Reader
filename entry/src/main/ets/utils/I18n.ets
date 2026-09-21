import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { i18n } from '@kit.LocalizationKit';

/**
 * Localisation runtime.
 *
 * Mirrors the original's use of `react-intl-universal`: locale JSON files with
 * dot-paths, `{name}` placeholders and ICU plural messages such as
 * `{count, plural, =1 {# article} other {# articles}}`.
 *
 * Only two locales ship — the original's own `zh-CN` and `en-US` packs. This
 * port deliberately stops there rather than carrying the upstream's other 17
 * packs: a translation nobody can review is worse than an honest English
 * fallback, and every string this port adds would otherwise show as English in
 * 17 half-localised UIs. Strings this port adds that upstream has no key for
 * live in `BUILTIN`, with English and Chinese variants; anything else falls
 * back to English rather than showing a raw key.
 */
export class I18n {
  private static messages: Record<string, Object> = {};
  private static fallback: Record<string, Object> = {};
  private static locale: string = 'en-US';
  private static ready: boolean = false;

  /** Locales bundled in rawfile. Chinese and English only, by design. */
  private static readonly LOCALES: string[] = ['en-US', 'zh-CN'];

  /**
   * Strings this port introduces. `en` is the guaranteed fallback; `zh` is
   * provided so the Chinese UI does not mix languages on the main surfaces.
   */
  private static readonly BUILTIN_EN: Record<string, string> = {
    'app.name': 'Sheaf Reader',
    'app.loading': 'Loading...',
    'app.articlesCount': '{count} articles',
    'app.noSubscriptions': 'No subscriptions yet',
    'app.addFeedHint': 'Tap + to add a feed',
    'app.syncOff': 'Sync service: off',
    'app.linkedFeeds': '{count} linked feeds',
    'app.syncing': 'Syncing...',
    'app.customised': 'Customised',
    'app.viewOptions': 'Display options',
    'app.noContent': 'No content available for this article.',
    'app.pickArticle': 'Pick an article from the list to read it here',
    'app.startHint': 'Add a subscription to get started',
    'app.refreshHint': 'Refresh to fetch the latest articles',
    'app.open': 'Open',
    'app.read': 'Read',
    'app.rules': 'Rules',
    'app.ruleAdded': 'Rule added. It applies to articles fetched from now on.',
    'app.ruleRemoved': 'Rule removed',
    'app.notifications': 'Notifications',
    'app.clear': 'Clear',
    'app.noNotifications': 'No notifications',
    'app.noRules': 'No rules for this source yet.',
    'app.newRule': 'New rule',
    'app.ruleRegex': 'Regular expression, e.g. \\[AD\\]|sponsored',
    'app.caseSensitive': 'Case sensitive',
    'app.addRule': 'Add rule',
    'app.readState': 'Read state',
    'app.visibility': 'Visibility',
    'app.notification': 'Notification',
    'app.if': 'If',
    'app.then': 'Then',
    'app.source': 'Source',
    'app.rulesIntro': 'Rules run in order, before an article is stored.',
    'app.rulePatternRequired': 'Enter a regular expression',
    'app.ruleInvalidRegex': 'Invalid regular expression',
    'app.ruleActionRequired': 'Select at least one action',
    'app.fetched': 'Fetched {count} new articles',
    'app.upToDate': 'Feeds are up to date',
    'app.fetchFailed': 'Failed to load source "{name}"',
    'app.fetchedOk': 'Successfully fetched {count} articles',
    'app.syncFailed': 'Failed to sync with service',
    'app.notifyFailed': 'Could not raise a system notification',
    'app.syncComplete': 'Sync complete: {items} new, {updates} state updates',
    'app.syncRunning': 'A sync is already running',
    'app.syncStarting': 'Starting',
    'app.syncingService': 'Syncing with service',
    'app.subscribedTo': 'Subscribed to {name}',
    'app.subscriptionRemoved': 'Subscription removed',
    'app.allMarkedRead': 'All articles marked as read',
    'app.groupDeleted': 'Group deleted',
    'app.groupCreated': 'Group "{name}" created',
    'app.noBrowser': 'No browser available',
    'app.noLink': 'This article has no link',
    'app.language': 'Display language',
    'app.theme': 'Theme',
    'app.data': 'Application data',
    'app.backup': 'Back up',
    'app.restore': 'Restore',
    'app.restoreHint': 'A backup contains every subscription, article and preference. Restoring replaces all current data.',
    'app.backupSaved': 'Backup saved',
    'app.backupInvalid': 'That file is not a Sheaf Reader backup',
    'app.backupRestored': 'Restored {feeds} subscriptions and {articles} articles',
    'app.backupSummary': '{feeds} subscriptions, {articles} articles',
    'app.confirmRestore': 'Restore this backup? All current subscriptions and articles will be replaced.',
    'app.authentication': 'Authentication',
    'app.account': 'Account',
    'app.clientLoginHint': 'Credentials are exchanged for a session token via ClientLogin.',
    'app.stripAdsHint': 'Strip the injected \"Ads from Inoreader\" block',
    'app.fetchLimitHint': 'Latest articles to pull',
    'app.wideIds': '64-bit entry ids',
    'app.wideIdsHint': 'Enable for The Old Reader, which issues ids wider than 64 bits',
    'app.subscriptionsCount': 'Subscriptions: {count}',
    'app.cachedArticles': 'Cached articles: {count}',
    'app.syncNow': 'Sync now',
    'app.removeService': 'Remove service',
    'app.save': 'Save',
    'app.builtinViewHint': 'Otherwise the system browser is used',
    'app.nothingSelected': 'Nothing selected',
    'app.reading': 'Reading',
    'app.sync': 'Sync',
    'app.serviceLinked': 'Service-linked: {count}',
    'app.syncService': 'Sync service',
    'app.noneLocalOnly': 'None (local only)',
    'app.googleReaderApi': 'Google Reader API',
    'app.authApiToken': 'API token (X-Auth-Token)',
    'app.authUsernamePassword': 'Username and password (Basic)',
    'app.apiToken': 'API token',
    'app.usernameOrEmail': 'Username or email',
    'app.appIdOptional': 'AppId (optional)',
    'app.appKeyOptional': 'AppKey (optional)',
    'app.testing': 'Testing...',
    'app.test': 'Test',
    'app.connecting': 'Connecting...',
    'app.connected': 'Connected successfully',
    'app.connectFailed': 'Cannot connect to service. Check the endpoint and credentials.',
    'app.enterEndpoint': 'Enter the service endpoint URL',
    'app.enterApiToken': 'Enter an API token',
    'app.enterUsernamePassword': 'Enter a username and password',
    'app.enterAccountCredentials': 'Enter your account username and password',
    'app.endpointHintInoreader': 'https://www.inoreader.com',
    'app.endpointHintGReader': 'https://theoldreader.com',
    'app.endpointHintLocal': 'https://reader.example.com',
    'app.noGroup': 'No Group',
    'app.myFeed': 'My Feed',
    'app.adding': 'Adding...',
    'app.enterFeedUrl': 'Enter a feed URL first',
    'app.feedAdded': 'Feed added',
    'app.feedExists': 'This feed is already subscribed',
    'app.feedInvalid': 'Could not read a feed at this address',
    'app.groupNameHint': 'Group name',
    'app.groupNameExists': 'A group with this name already exists',
    'app.copyFailed': 'Could not copy the link',
    'app.cacheCleared': 'Article cache cleaned',
    'app.importingFeeds': 'Importing subscriptions...',
    'app.importedFeeds': 'Imported {feeds} sources, {failed} failed',
    'app.nothingToExport': 'There are no subscriptions to export',
    'app.exportedFeeds': 'Exported {count} subscriptions',
    'app.rulesNeedSource': 'Add a subscription first - rules belong to a source',
    'app.serviceRemoved': 'Sync service removed',
    'app.deleteGroup': 'Delete group',
    'app.deleteGroupMessage': '"{name}" will be removed. Its subscriptions are kept and become ungrouped.',
    'app.thisSubscription': 'This subscription',
    'app.removeSubscription': 'Remove subscription',
    'app.removeFeedMessage': '{name} and its downloaded articles will be deleted.',
    'app.saving': 'Saving...',
    'app.feedSettingsSaved': 'Source settings saved',
    'app.basicAuthHint': 'Credentials are sent with every request using HTTP Basic authentication.',
    'app.feverAuthHint': 'Fever derives its API key from these as md5(email:password).',
    'app.groupRenamed': 'Group "{name}" renamed',
    'app.noImage': 'This article has no image',
    'app.imageFetchFailed': 'Could not download the image',
    'app.imageDecodeFailed': 'That file is not a readable image',
    'app.saveCancelled': 'Save cancelled',
    'app.imageSaved': 'Image saved',
    'app.imageCopied': 'Image copied',
    'app.imageLinkCopied': 'Image link copied',
    'app.ruleTestResult': '{matched} of {total} loaded articles match'
  };

  private static readonly BUILTIN_ZH: Record<string, string> = {
    'app.name': '束阅',
    'app.loading': '加载中…',
    'app.articlesCount': '{count} 篇',
    'app.noSubscriptions': '还没有订阅',
    'app.addFeedHint': '点击 + 添加订阅源',
    'app.syncOff': '同步服务：未启用',
    'app.linkedFeeds': '已关联 {count} 个订阅源',
    'app.syncing': '同步中…',
    'app.customised': '自定义',
    'app.viewOptions': '显示选项',
    'app.noContent': '这篇文章没有可显示的正文。',
    'app.pickArticle': '从列表中选择一篇文章在此阅读',
    'app.startHint': '添加一个订阅源即可开始',
    'app.refreshHint': '刷新以获取最新文章',
    'app.open': '打开',
    'app.read': '已读',
    'app.rules': '规则',
    'app.ruleAdded': '规则已添加，将对之后抓取的文章生效。',
    'app.ruleRemoved': '规则已删除',
    'app.notifications': '通知',
    'app.clear': '清空',
    'app.noNotifications': '暂无通知',
    'app.noRules': '该订阅源还没有规则。',
    'app.newRule': '新建规则',
    'app.ruleRegex': '正则表达式，例如 \\[AD\\]|sponsored',
    'app.caseSensitive': '区分大小写',
    'app.addRule': '添加规则',
    'app.readState': '已读状态',
    'app.visibility': '可见性',
    'app.notification': '通知',
    'app.if': '如果',
    'app.then': '则',
    'app.source': '订阅源',
    'app.rulesIntro': '规则按顺序执行，在文章入库之前生效。',
    'app.rulePatternRequired': '请输入正则表达式',
    'app.ruleInvalidRegex': '正则表达式无效',
    'app.ruleActionRequired': '请至少选择一个动作',
    'app.fetched': '已抓取 {count} 篇新文章',
    'app.upToDate': '订阅源已是最新',
    'app.fetchFailed': '加载订阅源「{name}」失败',
    'app.fetchedOk': '成功抓取 {count} 篇文章',
    'app.syncFailed': '与服务同步失败',
    'app.notifyFailed': '无法发出系统通知',
    'app.syncComplete': '同步完成：新增 {items} 篇，状态更新 {updates} 条',
    'app.syncRunning': '同步已在进行中',
    'app.syncStarting': '开始',
    'app.syncingService': '正在与服务同步',
    'app.subscribedTo': '已订阅 {name}',
    'app.subscriptionRemoved': '订阅已删除',
    'app.allMarkedRead': '已将全部文章标为已读',
    'app.groupDeleted': '分组已删除',
    'app.groupCreated': '已创建分组「{name}」',
    'app.noBrowser': '没有可用的浏览器',
    'app.noLink': '这篇文章没有链接',
    'app.language': '显示语言',
    'app.theme': '主题',
    'app.data': '应用数据',
    'app.backup': '备份',
    'app.restore': '恢复',
    'app.restoreHint': '备份包含全部订阅源、文章与偏好设置；恢复会覆盖当前所有数据。',
    'app.backupSaved': '备份已保存',
    'app.backupInvalid': '该文件不是束阅的备份',
    'app.backupRestored': '已恢复 {feeds} 个订阅源、{articles} 篇文章',
    'app.backupSummary': '{feeds} 个订阅源、{articles} 篇文章',
    'app.confirmRestore': '确定要恢复此备份吗？当前所有订阅源与文章都会被替换。',
    'app.authentication': '身份验证',
    'app.account': '账户',
    'app.clientLoginHint': '凭据将通过 ClientLogin 换取会话令牌。',
    'app.stripAdsHint': '移除注入的「Ads from Inoreader」区块',
    'app.fetchLimitHint': '拉取的最新文章数',
    'app.wideIds': '64 位条目 ID',
    'app.wideIdsHint': '适用于 The Old Reader，其条目 ID 超过 64 位',
    'app.subscriptionsCount': '订阅源：{count}',
    'app.cachedArticles': '已缓存文章：{count}',
    'app.syncNow': '立即同步',
    'app.removeService': '移除服务',
    'app.save': '保存',
    'app.builtinViewHint': '否则将使用系统浏览器',
    'app.nothingSelected': '未选择任何内容',
    'app.reading': '阅读',
    'app.sync': '同步',
    'app.serviceLinked': '已关联服务：{count}',
    'app.syncService': '同步服务',
    'app.noneLocalOnly': '无（仅本地）',
    'app.googleReaderApi': 'Google Reader API',
    'app.authApiToken': 'API 令牌（X-Auth-Token）',
    'app.authUsernamePassword': '用户名和密码（Basic）',
    'app.apiToken': 'API 令牌',
    'app.usernameOrEmail': '用户名或邮箱',
    'app.appIdOptional': 'AppId（可选）',
    'app.appKeyOptional': 'AppKey（可选）',
    'app.testing': '测试中…',
    'app.test': '测试',
    'app.connecting': '正在连接…',
    'app.connected': '连接成功',
    'app.connectFailed': '无法连接到服务，请检查端点与凭据。',
    'app.enterEndpoint': '请输入服务端点 URL',
    'app.enterApiToken': '请输入 API 令牌',
    'app.enterUsernamePassword': '请输入用户名和密码',
    'app.enterAccountCredentials': '请输入账户的用户名和密码',
    'app.endpointHintInoreader': 'https://www.inoreader.com',
    'app.endpointHintGReader': 'https://theoldreader.com',
    'app.endpointHintLocal': 'https://reader.example.com',
    'app.noGroup': '不分组',
    'app.myFeed': '我的订阅源',
    'app.adding': '添加中…',
    'app.enterFeedUrl': '请先输入订阅源 URL',
    'app.feedAdded': '订阅源已添加',
    'app.feedExists': '该订阅源已经订阅过了',
    'app.feedInvalid': '无法读取该地址的订阅源',
    'app.groupNameHint': '分组名称',
    'app.groupNameExists': '已存在同名分组',
    'app.copyFailed': '无法复制链接',
    'app.cacheCleared': '已清理文章缓存',
    'app.importingFeeds': '正在导入订阅源…',
    'app.importedFeeds': '已导入 {feeds} 个订阅源，{failed} 个失败',
    'app.nothingToExport': '没有可导出的订阅源',
    'app.exportedFeeds': '已导出 {count} 个订阅源',
    'app.rulesNeedSource': '请先添加订阅源——规则从属于订阅源',
    'app.serviceRemoved': '已移除同步服务',
    'app.deleteGroup': '删除分组',
    'app.deleteGroupMessage': '将移除「{name}」。其订阅源会保留并变为未分组。',
    'app.thisSubscription': '该订阅源',
    'app.removeSubscription': '移除订阅源',
    'app.removeFeedMessage': '将删除 {name} 及其已下载的文章。',
    'app.saving': '保存中…',
    'app.feedSettingsSaved': '订阅源设置已保存',
    'app.basicAuthHint': '凭据将通过 HTTP Basic 认证随每次请求发送。',
    'app.feverAuthHint': 'Fever 会用这两个值按 md5(email:password) 派生出 API 密钥。',
    'app.groupRenamed': '分组「{name}」已重命名',
    'app.noImage': '这篇文章没有图片',
    'app.imageFetchFailed': '无法下载图片',
    'app.imageDecodeFailed': '该文件不是可读的图片',
    'app.saveCancelled': '已取消保存',
    'app.imageSaved': '图片已保存',
    'app.imageCopied': '图片已复制',
    'app.imageLinkCopied': '图片链接已复制',
    'app.ruleTestResult': '已加载的 {total} 篇文章中有 {matched} 篇匹配'
  };

  /**
   * Load the locale messages. Missing files fall back to English; a failure
   * here must never stop the app from starting.
   */
  static async init(context: common.Context, requested: string): Promise<void> {
    const locale: string = I18n.normalize(requested);
    const messages: Record<string, Object> = await I18n.load(context, locale);
    const fallback: Record<string, Object> = locale === 'en-US'
      ? messages : await I18n.load(context, 'en-US');
    I18n.useMessages(locale, messages, fallback);
  }

  /**
   * Install a set of messages. Separate from `init` so the formatting logic
   * can be exercised without a device context.
   */
  static useMessages(locale: string, messages: Record<string, Object>,
    fallback: Record<string, Object>): void {
    I18n.locale = locale;
    I18n.messages = messages;
    I18n.fallback = fallback;
    I18n.ready = true;
  }

  /**
   * Pick a bundled locale for a requested tag: exact match, then language
   * prefix, then English — the same resolution the original uses. With only
   * Chinese and English bundled, every `zh-*` tag lands on `zh-CN` and
   * everything else lands on `en-US`.
   */
  static normalize(requested: string): string {
    if (!requested) {
      return 'en-US';
    }
    if (I18n.LOCALES.indexOf(requested) >= 0) {
      return requested;
    }
    // HarmonyOS reports tags like zh-Hans-CN; try the region form too.
    const parts: string[] = requested.split('-');
    if (parts.length >= 2) {
      const region: string = parts[0].concat('-').concat(parts[parts.length - 1]);
      if (I18n.LOCALES.indexOf(region) >= 0) {
        return region;
      }
    }
    const language: string = parts[0];
    for (const candidate of I18n.LOCALES) {
      if (candidate === language || candidate.startsWith(language.concat('-'))) {
        return candidate;
      }
    }
    return 'en-US';
  }

  private static async load(context: common.Context,
    locale: string): Promise<Record<string, Object>> {
    try {
      const bytes: Uint8Array =
        await context.resourceManager.getRawFileContent('i18n/'.concat(locale).concat('.json'));
      const text: string = util.TextDecoder.create('utf-8').decodeToString(bytes);
      return JSON.parse(text) as Record<string, Object>;
    } catch (err) {
      console.error('I18n: could not load locale ' + locale);
      return {};
    }
  }

  static currentLocale(): string {
    return I18n.locale;
  }

  static isReady(): boolean {
    return I18n.ready;
  }

  static availableLocales(): string[] {
    return I18n.LOCALES;
  }

  /**
   * The device's preferred language, normalised to a bundled locale.
   */
  static systemLocale(): string {
    try {
      return I18n.normalize(i18n.System.getSystemLanguage());
    } catch (err) {
      return 'en-US';
    }
  }

  /**
   * Human-readable name of a locale, for the language picker.
   */
  static localeLabel(locale: string): string {
    const names: Record<string, string> = {
      'en-US': 'English', 'zh-CN': '简体中文'
    };
    const name: string | undefined = names[locale];
    return name !== undefined ? name : locale;
  }

  /**
   * Translate `key`, substituting `args`. Falls back to the built-in English
   * string and finally to the key itself, so a missing translation degrades to
   * readable text rather than a raw identifier.
   */
  static get(key: string, args?: Map<string, string | number>): string {
    let template: string | null = I18n.lookup(I18n.messages, key);
    if (template === null) {
      template = I18n.lookup(I18n.fallback, key);
    }
    if (template === null) {
      const builtin: Record<string, string> =
        I18n.locale.startsWith('zh') ? I18n.BUILTIN_ZH : I18n.BUILTIN_EN;
      const localized: string | undefined = builtin[key];
      template = localized !== undefined ? localized : I18n.BUILTIN_EN[key];
    }
    if (template === undefined || template === null) {
      return key;
    }
    return I18n.format(template, args);
  }

  /**
   * Walk a dot path through the nested locale object.
   */
  private static lookup(root: Record<string, Object>, key: string): string | null {
    const parts: string[] = key.split('.');
    let current: Object = root;
    for (const part of parts) {
      if (current === undefined || current === null) {
        return null;
      }
      const node: Object = (current as Record<string, Object>)[part];
      if (node === undefined || node === null) {
        return null;
      }
      current = node;
    }
    return typeof current === 'string' ? current as string : null;
  }

  /**
   * Substitute `{name}` placeholders and evaluate `{name, plural, ...}`
   * clauses. Nested braces are matched by counting, since plural bodies
   * contain braces of their own.
   */
  private static format(template: string, args?: Map<string, string | number>): string {
    let out: string = '';
    let i: number = 0;

    while (i < template.length) {
      const open: number = template.indexOf('{', i);
      if (open < 0) {
        out = out.concat(template.substring(i));
        break;
      }
      out = out.concat(template.substring(i, open));

      const close: number = I18n.matchBrace(template, open);
      if (close < 0) {
        out = out.concat(template.substring(open));
        break;
      }

      const body: string = template.substring(open + 1, close);
      out = out.concat(I18n.resolve(body, args));
      i = close + 1;
    }

    return out;
  }

  /** Index of the `}` matching the `{` at `start`, or -1. */
  private static matchBrace(text: string, start: number): number {
    let depth: number = 0;
    for (let i = start; i < text.length; i++) {
      const ch: string = text.charAt(i);
      if (ch === '{') {
        depth++;
      } else if (ch === '}') {
        depth--;
        if (depth === 0) {
          return i;
        }
      }
    }
    return -1;
  }

  /**
   * Evaluate the inside of a `{...}`: a bare name, or `name, plural, cases`.
   */
  private static resolve(body: string, args?: Map<string, string | number>): string {
    const comma: number = body.indexOf(',');
    const name: string = (comma < 0 ? body : body.substring(0, comma)).trim();

    let value: string | number | undefined =
      args !== undefined ? args.get(name) : undefined;
    if (value === undefined) {
      return '';
    }

    if (comma < 0) {
      return value.toString();
    }

    const rest: string = body.substring(comma + 1).trim();
    if (!rest.startsWith('plural')) {
      // `number`/`select` are not used by the bundled locales.
      return value.toString();
    }

    const numeric: number = typeof value === 'number'
      ? value as number : Number.parseInt(value.toString(), 10);
    if (isNaN(numeric)) {
      return value.toString();
    }

    const cases: string = rest.substring('plural'.length).trim();
    const chosen: string | null = I18n.pickPluralCase(cases, numeric);
    if (chosen === null) {
      return value.toString();
    }
    // `#` inside a plural body stands for the number.
    return chosen.split('#').join(numeric.toString());
  }

  /**
   * Pick the clause for `count`, preferring an exact `=N` over `other`.
   */
  private static pickPluralCase(cases: string, count: number): string | null {
    let other: string | null = null;
    let i: number = 0;

    while (i < cases.length) {
      const brace: number = cases.indexOf('{', i);
      if (brace < 0) {
        break;
      }
      // The text before `{` is `, =1 ` / `, other ` — strip the leading comma
      // as well as trailing whitespace, or the exact-count clause never
      // matches and everything falls through to `other`.
      const selector: string = cases.substring(i, brace)
        .replace(/^[,\s]+/, '')
        .replace(/[,\s]+$/, '');
      const end: number = I18n.matchBrace(cases, brace);
      if (end < 0) {
        break;
      }
      const body: string = cases.substring(brace + 1, end);

      if (selector === 'other') {
        other = body;
      } else if (selector === '='.concat(count.toString())) {
        return body;
      }
      i = end + 1;
    }

    return other;
  }
}
