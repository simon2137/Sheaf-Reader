import { ServiceConfigs, SyncService } from '../model/Models';
import { HttpClient } from '../data/HttpClient';
import { I18n } from '../utils/I18n';
import { TouchTarget } from '../utils/TouchTarget';

/**
 * NOTE: upstream's `serviceOptions()` ends with a `service.suggest` entry whose
 * handler opens its issue tracker instead of selecting a service
 * (`onServiceOptionChange`: `if (option.key === -1) openExternal(...)`). This
 * port **deliberately does not offer it** (asked for by the user): linking a
 * HarmonyOS build to an Electron project's issue tracker invites reports the
 * upstream author cannot act on. This is an intentional deviation, not an
 * oversight — see README "与上游的差异".
 */
/** `rules.help`'s link target in the original's intro block. */
const SERVICE_HELP_URL: string =
  'https://github.com/yang991178/fluent-reader/wiki/Support#services';

/**
 * Sync-service configuration dialog.
 *
 * Mirrors the original's per-service settings panes:
 *  - Miniflux: endpoint, auth mode (`X-Auth-Token` vs Basic), fetch limit
 *  - GReader / Inoreader: endpoint, username + password (ClientLogin), fetch
 *    limit, 64-bit ids for The Old Reader, and Inoreader's app credentials
 *    plus ad-stripping toggle
 */
@CustomDialog
export struct ServiceSettingsDialog {
  @Prop isDarkMode: boolean;
  @Prop initialConfigs: ServiceConfigs;
  @Prop feedCount: number;
  @Prop linkedCount: number;

  onSave: (configs: ServiceConfigs) => void = () => {
  };
  /**
   * Save-then-sync in one call. Passing the configs avoids a race where the
   * sync reads the previous configuration because the async save has not
   * completed yet.
   */
  onSyncNow: (configs: ServiceConfigs) => void = () => {
  };
  onRemove: () => void = () => {
  };
  onTest: (configs: ServiceConfigs) => Promise<boolean> =
    async () => false;
  /**
   * Open an https URL in the system browser. Used by the intro block's "Learn
   * more" link, which the original opens externally
   * (`window.utils.openExternal`).
   */
  onOpenUrl: (url: string) => void = () => {
  };

  controller?: CustomDialogController;

  @State serviceType: number = SyncService.None;
  @State endpoint: string = '';
  @State fetchLimit: number = 1000;
  @State importGroups: boolean = false;
  @State status: string = '';
  @State testing: boolean = false;
  /**
   * Index shown by the service picker.
   *
   * A `@State` drives `.value()` rather than a call over `serviceType`: the
   * display has to follow the tap immediately, and a value recomputed from an
   * unchanged `serviceType` would not re-render (defect ⑤/⑱).
   */
  @State servicePick: number = 0;

  /* Miniflux */
  @State useApiKey: boolean = true;
  @State apiKey: string = '';

  /* GReader / Inoreader */
  @State username: string = '';
  @State password: string = '';
  @State useInt64: boolean = false;
  @State inoreaderId: string = '';
  @State inoreaderKey: string = '';
  @State removeInoreaderAd: boolean = true;

  aboutToAppear(): void {
    const c: ServiceConfigs = this.initialConfigs;
    this.serviceType = c.type;
    this.servicePick = this.servicePickIndex();
    this.endpoint = c.endpoint;
    this.useApiKey = c.apiKeyAuth;
    this.apiKey = c.apiKeyAuth ? c.authKey : '';
    this.fetchLimit = c.fetchLimit;
    this.importGroups = c.importGroups;
    this.username = c.username;
    this.password = c.password;
    this.useInt64 = c.useInt64;
    this.inoreaderId = c.inoreaderId;
    this.inoreaderKey = c.inoreaderKey;
    this.removeInoreaderAd = c.removeInoreaderAd;
  }

  private textColor(): string {
    return this.isDarkMode ? '#E8E6E3' : '#323130';
  }

  private secondaryColor(): string {
    return this.isDarkMode ? '#A19F9D' : '#605E5C';
  }

  private surfaceColor(): string {
    return this.isDarkMode ? '#252423' : '#FFFFFF';
  }

  private fieldColor(): string {
    return this.isDarkMode ? '#323130' : '#F3F2F1';
  }

  private dividerColor(): string {
    return this.isDarkMode ? '#3B3A39' : '#EDEBE9';
  }

  private closeDialog(): void {
    if (this.controller !== undefined) {
      this.controller.close();
    }
  }

  private isGReaderFamily(): boolean {
    return this.serviceType === SyncService.GReader
      || this.serviceType === SyncService.Inoreader;
  }

  private isInoreader(): boolean {
    return this.serviceType === SyncService.Inoreader;
  }

  /**
   * Feedbin and Nextcloud News: JSON REST with HTTP Basic auth.
   */
  private isRestFamily(): boolean {
    return this.serviceType === SyncService.Feedbin
      || this.serviceType === SyncService.Nextcloud;
  }

  private isFever(): boolean {
    return this.serviceType === SyncService.Fever;
  }

  /**
   * Services configured with a plain username/password form. Fever derives its
   * `api_key` from them, the other two send them as an HTTP Basic header.
   */
  private usesPasswordAuth(): boolean {
    return this.isRestFamily() || this.isFever();
  }

  /**
   * Index into the service Select, whose option order is fixed below.
   */
  private serviceTypeAt(index: number): number {
    switch (index) {
      case 1:
        return SyncService.Miniflux;
      case 2:
        return SyncService.GReader;
      case 3:
        return SyncService.Inoreader;
      case 4:
        return SyncService.Feedbin;
      case 5:
        return SyncService.Nextcloud;
      case 6:
        return SyncService.Fever;
      default:
        return SyncService.None;
    }
  }

  /** Display label for a picker index, product names included. */
  private serviceLabelAt(index: number): string {
    switch (index) {
      case 1:
        return 'Miniflux';
      case 2:
        return I18n.get('app.googleReaderApi');
      case 3:
        return 'Inoreader';
      case 4:
        return 'Feedbin';
      case 5:
        return 'Nextcloud News';
      case 6:
        return 'Fever';
      default:
        return I18n.get('app.noneLocalOnly');
    }
  }

  /** Picker index of the currently configured service. */
  private servicePickIndex(): number {
    switch (this.serviceType) {
      case SyncService.Miniflux:
        return 1;
      case SyncService.GReader:
        return 2;
      case SyncService.Inoreader:
        return 3;
      case SyncService.Feedbin:
        return 4;
      case SyncService.Nextcloud:
        return 5;
      case SyncService.Fever:
        return 6;
      default:
        return 0;
    }
  }

  private endpointHint(): string {
    if (this.isInoreader()) {
      return I18n.get('app.endpointHintInoreader');
    }
    if (this.serviceType === SyncService.GReader) {
      return I18n.get('app.endpointHintGReader');
    }
    if (this.serviceType === SyncService.Feedbin) {
      return 'https://api.feedbin.com';
    }
    if (this.serviceType === SyncService.Nextcloud) {
      return 'https://cloud.example.com';
    }
    if (this.isFever()) {
      return 'https://fever.example.com';
    }
    return I18n.get('app.endpointHintLocal');
  }

  /**
   * Build the configuration the user has entered.
   *
   * The stored `auth` token is carried over only when the service, endpoint
   * and username are unchanged; otherwise it is dropped so the next sync
   * performs a fresh ClientLogin with the new credentials.
   */
  private buildConfigs(): ServiceConfigs {
    const configs: ServiceConfigs = new ServiceConfigs();
    configs.type = this.serviceType;
    configs.endpoint = this.endpoint.trim();
    configs.fetchLimit = this.fetchLimit;
    configs.importGroups = this.importGroups;

    if (this.serviceType === SyncService.Miniflux) {
      configs.apiKeyAuth = this.useApiKey;
      configs.authKey = this.useApiKey
        ? this.apiKey.trim()
        : HttpClient.basicAuthValue(this.username.trim(), this.password);
    }

    if (this.isGReaderFamily()) {
      configs.username = this.username.trim();
      configs.password = this.password;
      configs.useInt64 = this.useInt64;
      configs.inoreaderId = this.inoreaderId.trim();
      configs.inoreaderKey = this.inoreaderKey.trim();
      configs.removeInoreaderAd = this.removeInoreaderAd;
    }

    if (this.usesPasswordAuth()) {
      // Feedbin and Nextcloud authenticate with HTTP Basic; Fever derives its
      // `api_key` from the same pair. The fields are stored as well as the
      // encoded header, because the dialog repopulates from them and without
      // them a reopened dialog fails validation.
      configs.username = this.username.trim();
      configs.password = this.password;
    }

    if (this.isRestFamily()) {
      configs.apiKeyAuth = false;
      configs.authKey = HttpClient.basicAuthValue(this.username.trim(), this.password);
    }

    // Cursors only make sense for the same remote account.
    const sameService: boolean = this.initialConfigs.type === this.serviceType;
    const sameEndpoint: boolean = this.initialConfigs.endpoint === configs.endpoint;
    const sameUser: boolean = this.initialConfigs.username === configs.username;
    if (sameService && sameEndpoint && sameUser) {
      configs.lastId = this.initialConfigs.lastId;
      configs.lastIdRef = this.initialConfigs.lastIdRef;
      configs.lastFetched = this.initialConfigs.lastFetched;
      configs.auth = this.initialConfigs.auth;
    }

    return configs;
  }

  private validate(): string {
    if (this.serviceType === SyncService.None) {
      return '';
    }
    // Feedbin is a hosted service, so an empty endpoint means the public API.
    if (this.serviceType !== SyncService.Feedbin && this.endpoint.trim().length === 0) {
      return I18n.get('app.enterEndpoint');
    }
    if (this.serviceType === SyncService.Miniflux) {
      if (this.useApiKey && this.apiKey.trim().length === 0) {
        return I18n.get('app.enterApiToken');
      }
      if (!this.useApiKey
        && (this.username.trim().length === 0 || this.password.length === 0)) {
        return I18n.get('app.enterUsernamePassword');
      }
      return '';
    }
    if (this.isGReaderFamily()) {
      if (this.username.trim().length === 0 || this.password.length === 0) {
        return I18n.get('app.enterAccountCredentials');
      }
    }
    if (this.isRestFamily()) {
      if (this.username.trim().length === 0 || this.password.length === 0) {
        return I18n.get('app.enterUsernamePassword');
      }
    }
    if (this.isFever()) {
      if (this.username.trim().length === 0 || this.password.length === 0) {
        return I18n.get('app.enterUsernamePassword');
      }
    }
    return '';
  }

  build() {
    Column() {
      // Header
      Row() {
        Text(I18n.get('settings.service'))
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.textColor())
          .layoutWeight(1)
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ic_close')).width(16).height(16).fillColor(this.secondaryColor())
        }
        .width(30)
        .height(30)
        .responseRegion(TouchTarget.region(30))
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.closeDialog();
        })
      }
      .width('100%')
      .padding({ bottom: 12 })

      Divider().color(this.dividerColor()).strokeWidth(1)

      Scroll() {
        Column() {
          Text(I18n.get('settings.service'))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.secondaryColor())
            .width('100%')
            .margin({ top: 14, bottom: 8 })

          Select([
            { value: I18n.get('app.noneLocalOnly') },
            { value: 'Miniflux' },
            { value: I18n.get('app.googleReaderApi') },
            { value: 'Inoreader' },
            { value: 'Feedbin' },
            { value: 'Nextcloud News' },
            { value: 'Fever' }
          ])
            .selected(this.servicePick)
            .value(this.serviceLabelAt(this.servicePick))
            .width('100%')
            .onSelect((index: number) => {
              this.servicePick = index;
              this.serviceType = this.serviceTypeAt(index);
              this.status = '';
            })

          /*
           * Upstream's intro block, shown while no service is configured:
           * `service.intro` plus a `rules.help` link that opens the wiki.
           */
          if (this.serviceType === SyncService.None) {
            Row() {
              Text(I18n.get('service.intro'))
                .fontSize(12)
                .fontColor(this.secondaryColor())
                .layoutWeight(1)

              Text(I18n.get('rules.help'))
                .fontSize(12)
                .fontColor('#0078D4')
                .margin({ left: 6 })
                .onClick(() => {
                  this.onOpenUrl(SERVICE_HELP_URL);
                })
            }
            .width('100%')
            .margin({ top: 8, bottom: 4 })
          }

          if (this.serviceType !== SyncService.None) {
            Text(I18n.get('service.endpoint'))
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.secondaryColor())
              .width('100%')
              .margin({ top: 16, bottom: 6 })

            TextInput({ placeholder: this.endpointHint(), text: this.endpoint })
              .width('100%')
              .height(40)
              .fontSize(14)
              .backgroundColor(this.fieldColor())
              .fontColor(this.textColor())
              .placeholderColor(this.secondaryColor())
              .onChange((value: string) => {
                this.endpoint = value;
                this.status = '';
              })
          }

          /* ---------------------------------------------- Miniflux auth */
          if (this.serviceType === SyncService.Miniflux) {
            Text(I18n.get('app.authentication'))
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.secondaryColor())
              .width('100%')
              .margin({ top: 16, bottom: 6 })

            Select([
              { value: I18n.get('app.authApiToken') },
              { value: I18n.get('app.authUsernamePassword') }
            ])
              .selected(this.useApiKey ? 0 : 1)
              .value(this.useApiKey ? I18n.get('app.apiToken') : I18n.get('app.authUsernamePassword'))
              .width('100%')
              .onSelect((index: number) => {
                this.useApiKey = index === 0;
                this.status = '';
              })

            if (this.useApiKey) {
              TextInput({ placeholder: I18n.get('app.apiToken'), text: this.apiKey })
                .width('100%')
                .height(40)
                .fontSize(14)
                .backgroundColor(this.fieldColor())
                .fontColor(this.textColor())
                .placeholderColor(this.secondaryColor())
                .margin({ top: 10 })
                .onChange((value: string) => {
                  this.apiKey = value;
                  this.status = '';
                })
            } else {
              TextInput({ placeholder: I18n.get('service.username'), text: this.username })
                .width('100%')
                .height(40)
                .fontSize(14)
                .backgroundColor(this.fieldColor())
                .fontColor(this.textColor())
                .placeholderColor(this.secondaryColor())
                .margin({ top: 10 })
                .onChange((value: string) => {
                  this.username = value;
                  this.status = '';
                })

              TextInput({ placeholder: I18n.get('service.password'), text: this.password })
                .type(InputType.Password)
                .width('100%')
                .height(40)
                .fontSize(14)
                .backgroundColor(this.fieldColor())
                .fontColor(this.textColor())
                .placeholderColor(this.secondaryColor())
                .margin({ top: 10 })
                .onChange((value: string) => {
                  this.password = value;
                  this.status = '';
                })
            }
          }

          /* ----------------------------- Feedbin / Nextcloud / Fever credentials */
          if (this.usesPasswordAuth()) {
            Text(I18n.get('app.account'))
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.secondaryColor())
              .width('100%')
              .margin({ top: 16, bottom: 6 })

            Text(I18n.get(this.isFever() ? 'app.feverAuthHint' : 'app.basicAuthHint'))
              .fontSize(11)
              .fontColor(this.secondaryColor())
              .width('100%')
              .margin({ bottom: 8 })

            TextInput({ placeholder: I18n.get('app.usernameOrEmail'), text: this.username })
              .width('100%')
              .height(40)
              .fontSize(14)
              .backgroundColor(this.fieldColor())
              .fontColor(this.textColor())
              .placeholderColor(this.secondaryColor())
              .onChange((value: string) => {
                this.username = value;
                this.status = '';
              })

            TextInput({ placeholder: I18n.get('service.password'), text: this.password })
              .type(InputType.Password)
              .width('100%')
              .height(40)
              .fontSize(14)
              .backgroundColor(this.fieldColor())
              .fontColor(this.textColor())
              .placeholderColor(this.secondaryColor())
              .margin({ top: 10 })
              .onChange((value: string) => {
                this.password = value;
                this.status = '';
              })
          }

          /* ---------------------------------------- GReader credentials */
          if (this.isGReaderFamily()) {
            Text(I18n.get('app.account'))
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.secondaryColor())
              .width('100%')
              .margin({ top: 16, bottom: 6 })

            Text(I18n.get('app.clientLoginHint'))
              .fontSize(11)
              .fontColor(this.secondaryColor())
              .width('100%')
              .margin({ bottom: 8 })

            TextInput({ placeholder: I18n.get('app.usernameOrEmail'), text: this.username })
              .width('100%')
              .height(40)
              .fontSize(14)
              .backgroundColor(this.fieldColor())
              .fontColor(this.textColor())
              .placeholderColor(this.secondaryColor())
              .onChange((value: string) => {
                this.username = value;
                this.status = '';
              })

            TextInput({ placeholder: I18n.get('service.password'), text: this.password })
              .type(InputType.Password)
              .width('100%')
              .height(40)
              .fontSize(14)
              .backgroundColor(this.fieldColor())
              .fontColor(this.textColor())
              .placeholderColor(this.secondaryColor())
              .margin({ top: 10 })
              .onChange((value: string) => {
                this.password = value;
                this.status = '';
              })
          }

          /* ------------------------------------------- Inoreader extras */
          if (this.isInoreader()) {
            Text('INOREADER')
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.secondaryColor())
              .width('100%')
              .margin({ top: 16, bottom: 6 })

            Text(I18n.get('service.rateLimitWarning'))
              .fontSize(11)
              .fontColor(this.secondaryColor())
              .width('100%')
              .margin({ bottom: 8 })

            TextInput({ placeholder: I18n.get('app.appIdOptional'), text: this.inoreaderId })
              .width('100%')
              .height(40)
              .fontSize(14)
              .backgroundColor(this.fieldColor())
              .fontColor(this.textColor())
              .placeholderColor(this.secondaryColor())
              .onChange((value: string) => {
                this.inoreaderId = value;
              })

            TextInput({ placeholder: I18n.get('app.appKeyOptional'), text: this.inoreaderKey })
              .width('100%')
              .height(40)
              .fontSize(14)
              .backgroundColor(this.fieldColor())
              .fontColor(this.textColor())
              .placeholderColor(this.secondaryColor())
              .margin({ top: 10 })
              .onChange((value: string) => {
                this.inoreaderKey = value;
              })

            Row() {
              Column() {
                Text(I18n.get('service.removeAd'))
                  .fontSize(14)
                  .fontColor(this.textColor())
                  .width('100%')
                Text(I18n.get('app.stripAdsHint'))
                  .fontSize(11)
                  .fontColor(this.secondaryColor())
                  .width('100%')
                  .margin({ top: 2 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Toggle({ type: ToggleType.Switch, isOn: this.removeInoreaderAd })
                .selectedColor('#0078D4')
                .onChange((isOn: boolean) => {
                  this.removeInoreaderAd = isOn;
                })
            }
            .width('100%')
            .margin({ top: 14 })
          }

          /* ----------------------------------------------- shared opts */
          if (this.serviceType !== SyncService.None) {
            Text(I18n.get('service.fetchLimit'))
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.secondaryColor())
              .width('100%')
              .margin({ top: 16, bottom: 6 })

            Row() {
              Text(I18n.get('app.fetchLimitHint'))
                .fontSize(14)
                .fontColor(this.textColor())
                .layoutWeight(1)
              Select([
                { value: '200' },
                { value: '500' },
                { value: '1000' },
                { value: '5000' },
                { value: I18n.get('service.fetchUnlimited') }
              ])
                .selected(this.fetchLimitIndex())
                .value(this.fetchLimitLabel())
                .width(140)
                .onSelect((index: number) => {
                  const limits: number[] = [200, 500, 1000, 5000, 1000000];
                  this.fetchLimit = limits[index];
                })
            }
            .width('100%')

            if (this.serviceType === SyncService.GReader) {
              Row() {
                Column() {
                  Text(I18n.get('app.wideIds'))
                    .fontSize(14)
                    .fontColor(this.textColor())
                    .width('100%')
                  Text(I18n.get('app.wideIdsHint'))
                    .fontSize(11)
                    .fontColor(this.secondaryColor())
                    .width('100%')
                    .margin({ top: 2 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Toggle({ type: ToggleType.Switch, isOn: this.useInt64 })
                  .selectedColor('#0078D4')
                  .onChange((isOn: boolean) => {
                    this.useInt64 = isOn;
                  })
              }
              .width('100%')
              .margin({ top: 14 })
            }
          }

          /* --------------------------------------------------- groups */
          if (this.serviceType !== SyncService.None) {
            Row() {
              Column() {
                Text(I18n.get('service.importGroups'))
                  .fontSize(14)
                  .fontColor(this.textColor())
                  .width('100%')
                Text(I18n.get('service.groupsWarning'))
                  .fontSize(11)
                  .fontColor(this.secondaryColor())
                  .width('100%')
                  .margin({ top: 2 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Toggle({ type: ToggleType.Switch, isOn: this.importGroups })
                .selectedColor('#0078D4')
                .onChange((isOn: boolean) => {
                  this.importGroups = isOn;
                })
            }
            .width('100%')
            .margin({ top: 14 })

            Row() {
              Text(I18n.get('app.subscriptionsCount', new Map<string, string | number>([['count', this.feedCount]]))
                + '   |   ' + I18n.get('app.serviceLinked',
                  new Map<string, string | number>([['count', this.linkedCount]])))
                .fontSize(12)
                .fontColor(this.secondaryColor())
                .layoutWeight(1)
            }
            .width('100%')
            .margin({ top: 14 })
          }

          if (this.status.length > 0) {
            Row() {
              Text(this.status)
                .fontSize(12)
                .fontColor('#0078D4')
                .layoutWeight(1)
            }
            .width('100%')
            .padding(8)
            .borderRadius(4)
            .backgroundColor(this.isDarkMode ? '#1F2A37' : '#EFF6FC')
            .margin({ top: 14 })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Auto)
      .align(Alignment.Top)

      Divider().color(this.dividerColor()).strokeWidth(1).margin({ top: 12 })

      // Actions
      if (this.serviceType !== SyncService.None) {
        Row() {
          Button(this.testing ? I18n.get('app.testing') : I18n.get('app.test'))
            .fontSize(13)
            .fontColor(this.textColor())
            .backgroundColor(this.fieldColor())
            .layoutWeight(1)
            .enabled(!this.testing)
            .onClick(async () => {
              const error: string = this.validate();
              if (error.length > 0) {
                this.status = error;
                return;
              }
              this.testing = true;
              this.status = I18n.get('app.connecting');
              const ok: boolean = await this.onTest(this.buildConfigs());
              this.testing = false;
              this.status = ok
                ? I18n.get('app.connected')
                : I18n.get('app.connectFailed');
            })

          Button(I18n.get('app.syncNow'))
            .fontSize(13)
            .fontColor(this.textColor())
            .backgroundColor(this.fieldColor())
            .layoutWeight(1)
            .margin({ left: 8 })
            .onClick(() => {
              const error: string = this.validate();
              if (error.length > 0) {
                this.status = error;
                return;
              }
              this.onSyncNow(this.buildConfigs());
              this.closeDialog();
            })
        }
        .width('100%')
        .margin({ top: 10 })
      }

      Row() {
        Button(I18n.get('app.removeService'))
          .fontSize(13)
          .fontColor('#D13438')
          .backgroundColor(this.fieldColor())
          .layoutWeight(1)
          .enabled(this.initialConfigs.type !== SyncService.None)
          .onClick(() => {
            this.onRemove();
            this.closeDialog();
          })

        Button(I18n.get('app.save'))
          .fontSize(13)
          .fontColor(Color.White)
          .backgroundColor('#0078D4')
          .layoutWeight(1)
          .margin({ left: 8 })
          .onClick(() => {
            const error: string = this.validate();
            if (error.length > 0) {
              this.status = error;
              return;
            }
            this.onSave(this.buildConfigs());
            this.closeDialog();
          })
      }
      .width('100%')
      .margin({ top: 10 })
    }
    .width(560)
    .height(720)
    .padding(24)
    .backgroundColor(this.surfaceColor())
    .borderRadius(10)
  }

  private fetchLimitIndex(): number {
    const limits: number[] = [200, 500, 1000, 5000, 1000000];
    const index: number = limits.indexOf(this.fetchLimit);
    return index >= 0 ? index : 2;
  }

  private fetchLimitLabel(): string {
    return this.fetchLimit >= 1000000 ? I18n.get('service.fetchUnlimited')
      : this.fetchLimit.toString();
  }
}
