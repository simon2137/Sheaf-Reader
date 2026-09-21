# Transpiles the shipped parser sources with a TypeScript compiler and runs the
# behavioural assertions under Node.
#
#   pwsh -File verify/run.ps1
#
# The compiler is looked up in this order, so the script works on any machine
# with DevEco Studio installed without editing it:
#   1. $env:VERIFY_TSC                      (explicit path to tsc.js)
#   2. <DevEco>/sdk/default/openharmony/... (the SDK bundled with DevEco Studio)
#   3. <DevEco>/sdk/default/hms/...         (alternative SDK layout)
#   4. verify/node_modules/typescript/...   (npm i typescript inside verify/)
#   5. $env:DEVECO_SDK_HOME variants of 2 and 3
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$here = $PSScriptRoot

$tscSuffix = "ets\build-tools\ets-loader\node_modules\typescript\lib\tsc.js"
$candidates = New-Object System.Collections.Generic.List[string]
if ($env:VERIFY_TSC) { $candidates.Add($env:VERIFY_TSC) }
$sdkRoots = New-Object System.Collections.Generic.List[string]
$sdkRoots.Add("C:\Program Files\Huawei\DevEco Studio\sdk")
$sdkRoots.Add("C:\Program Files\Huawei\DevEco Studio\sdk\default")
if ($env:DEVECO_SDK_HOME) { $sdkRoots.Add($env:DEVECO_SDK_HOME) }
if ($env:DEVECO_SDK_HOME) { $sdkRoots.Add((Join-Path $env:DEVECO_SDK_HOME "default")) }
foreach ($sdk in $sdkRoots) {
    $candidates.Add((Join-Path $sdk ("default\openharmony\" + $tscSuffix)))
    $candidates.Add((Join-Path $sdk ("openharmony\" + $tscSuffix)))
    $candidates.Add((Join-Path $sdk ("default\hms\" + $tscSuffix)))
    $candidates.Add((Join-Path $sdk ("hms\" + $tscSuffix)))
}
$candidates.Add((Join-Path $here "node_modules\typescript\lib\tsc.js"))

$tsc = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $tsc) {
    Write-Error ("TypeScript compiler not found. Set VERIFY_TSC to its path, or install " +
        "DevEco Studio / run 'npm i typescript' inside verify/. Searched:`n  " +
        ($candidates -join "`n  "))
}
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Error "Node.js is required to run the harness (node not found on PATH)."
}
Write-Host "Using TypeScript: $tsc"

# --- Stage the real sources as .ts -----------------------------------------
New-Item -ItemType Directory -Force -Path "$here\src\model", "$here\src\utils", "$here\src\services", "$here\src\data" | Out-Null

# Models.ets uses the ArkTS global @Observed decorator; provide a runtime no-op.
$models = Get-Content "$root\entry\src\main\ets\model\Models.ets" -Raw
Set-Content -Path "$here\src\model\Models.ts" -Value ("const Observed: any = () => {};`n" + $models) -Encoding utf8

Copy-Item "$root\entry\src\main\ets\utils\FeedParser.ets" "$here\src\utils\FeedParser.ts" -Force
Copy-Item "$root\entry\src\main\ets\utils\UrlUtils.ets"   "$here\src\utils\UrlUtils.ts"   -Force

# The full-content extractor is pure string work built on FeedParser, so it
# runs under Node unchanged.
Copy-Item "$root\entry\src\main\ets\utils\ContentExtractor.ets" "$here\src\utils\ContentExtractor.ts" -Force

# The sidebar's manual ordering is pure list maths, so it runs under Node too.
Copy-Item "$root\entry\src\main\ets\utils\ListOrder.ets" "$here\src\utils\ListOrder.ts" -Force

# Search-engine URL construction is pure string work.
Copy-Item "$root\entry\src\main\ets\utils\SearchEngines.ets" "$here\src\utils\SearchEngines.ts" -Force

# Storage accounting (article byte sizes, the MB rendering) is pure as well.
Copy-Item "$root\entry\src\main\ets\utils\StorageSize.ets" "$here\src\utils\StorageSize.ts" -Force

# Day arithmetic shared by the delete-articles and mark-read menus.
Copy-Item "$root\entry\src\main\ets\utils\TimeBounds.ets" "$here\src\utils\TimeBounds.ts" -Force

# Source scopes for the group / source context menu.
Copy-Item "$root\entry\src\main\ets\utils\ScopeFilter.ets" "$here\src\utils\ScopeFilter.ts" -Force

# The sidebar's "unread sources only" rule.
Copy-Item "$root\entry\src\main\ets\utils\SourceFilter.ets" "$here\src\utils\SourceFilter.ts" -Force

# The sidebar's visibility breakpoint.
Copy-Item "$root\entry\src\main\ets\utils\SidebarState.ets" "$here\src\utils\SidebarState.ts" -Force

# The per-source fetch-frequency rule shared by the fetch loop and the timer.
Copy-Item "$root\entry\src\main\ets\utils\FetchSchedule.ets" "$here\src\utils\FetchSchedule.ts" -Force

# Touch-target sizing (pure arithmetic on top of the UX guidance's 40vp rule).
# Its return type is ArkUI's global `Rectangle`, which does not exist under Node,
# so a structural declaration is prepended the way `Observed` is for Models.
$tt = [System.IO.File]::ReadAllText("$root\entry\src\main\ets\utils\TouchTarget.ets", [System.Text.Encoding]::UTF8)
$rectStub = "type Rectangle = { x?: number; y?: number; width?: number; height?: number };`n"
[System.IO.File]::WriteAllText("$here\src\utils\TouchTarget.ts", $rectStub + $tt, (New-Object System.Text.UTF8Encoding($false)))

# The reader's HTML-to-blocks splitter (paragraphs plus inline images).
Copy-Item "$root\entry\src\main\ets\utils\ReaderBody.ets" "$here\src\utils\ReaderBody.ts" -Force

# ImageActions only needs its kit imports for save/copy; the file-name
# derivation is pure and is what gets asserted, so the imports are stubbed out.
$ia = [System.IO.File]::ReadAllText("$root\entry\src\main\ets\utils\ImageActions.ets", [System.Text.Encoding]::UTF8)
$ia = $ia -replace "import \{ image \} from '@kit\.ImageKit';", "const image: any = {};"
$ia = $ia -replace "import \{ pasteboard \} from '@kit\.BasicServicesKit';", "const pasteboard: any = {};"
$ia = $ia -replace "import \{ common \} from '@kit\.AbilityKit';", "type common = any;"
$ia = $ia -replace "import \{ HttpClient \} from '\.\./data/HttpClient';", "const HttpClient: any = {};"
$ia = $ia -replace "import \{ OpmlFileService \} from './OpmlFileService';", "const OpmlFileService: any = {};"
[System.IO.File]::WriteAllText("$here\src\utils\ImageActionsStub.ts", "// @ts-nocheck`n" + $ia, (New-Object System.Text.UTF8Encoding($false)))

# Rule engine and its filter model are pure logic with no HarmonyOS kit
# imports, so they run directly under Node.
Copy-Item "$root\entry\src\main\ets\model\Filter.ets"           "$here\src\model\Filter.ts"        -Force
Copy-Item "$root\entry\src\main\ets\services\RuleEngine.ets"    "$here\src\services\RuleEngine.ts" -Force

# FeedFetcher imports HarmonyOS kits; keep only its pure helpers under Node.
$ff = Get-Content "$root\entry\src\main\ets\utils\FeedFetcher.ets" -Raw
$ff = $ff -replace "import \{ http \} from '@kit\.NetworkKit';", "const http: any = {};"
$ff = $ff -replace "import \{ BusinessError \} from '@kit\.BasicServicesKit';", "const BusinessError: any = undefined;"
Set-Content -Path "$here\src\utils\FeedFetcherStub.ts" -Value ("// @ts-nocheck`n" + $ff) -Encoding utf8

# I18n imports the AbilityKit / ArkTS / LocalizationKit; the lookup, plural and
# interpolation logic under test needs none of them.
# Note: I18n.ets contains non-ASCII strings, so read and write it as explicit
# UTF-8 — the default PowerShell encoding corrupts them into broken literals.
$i18n = [System.IO.File]::ReadAllText("$root\entry\src\main\ets\utils\I18n.ets", [System.Text.Encoding]::UTF8)
$i18n = $i18n -replace "import \{ common \} from '@kit\.AbilityKit';", "type common = any;"
$i18n = $i18n -replace "import \{ util \} from '@kit\.ArkTS';", "const util: any = {};"
$i18n = $i18n -replace "import \{ i18n \} from '@kit\.LocalizationKit';", "const i18n: any = { System: { getSystemLanguage: () => 'en-US' } };"
# Staged as I18n.ts (not I18nStub.ts) so that SearchEngines' own `./I18n`
# import resolves to this same module instance — a second copy would keep its
# own static message table and the label assertions would read empty messages.
[System.IO.File]::WriteAllText("$here\src\utils\I18n.ts", "// @ts-nocheck`n" + $i18n, (New-Object System.Text.UTF8Encoding($false)))
Remove-Item "$here\src\utils\I18nStub.ts" -ErrorAction SilentlyContinue

# HttpClient is pure apart from three kit imports; the URL normalisers for each
# sync service are what get asserted here.
$hc = [System.IO.File]::ReadAllText("$root\entry\src\main\ets\data\HttpClient.ets", [System.Text.Encoding]::UTF8)
$hc = $hc -replace "import \{ http \} from '@kit\.NetworkKit';", "const http: any = {};"
$hc = $hc -replace "import \{ BusinessError \} from '@kit\.BasicServicesKit';", "const BusinessError: any = undefined;"
$hc = $hc -replace "import \{ util \} from '@kit\.ArkTS';", "const util: any = {};"
$hc = $hc -replace "import \{ cryptoFramework \} from '@kit\.CryptoArchitectureKit';", "const cryptoFramework: any = {};"
[System.IO.File]::WriteAllText("$here\src\data\HttpClientStub.ts", "// @ts-nocheck`n" + $hc, (New-Object System.Text.UTF8Encoding($false)))

# BackupService only touches the database in export/import; the format parsing
# and the describe() summary are pure and are what get asserted here.
$bs = [System.IO.File]::ReadAllText("$root\entry\src\main\ets\services\BackupService.ets", [System.Text.Encoding]::UTF8)
$bs = $bs -replace "import \{ DatabaseManager \} from '\.\./data/DatabaseManager';", "const DatabaseManager: any = { getInstance: () => ({}) };"
[System.IO.File]::WriteAllText("$here\src\services\BackupServiceStub.ts", "// @ts-nocheck`n" + $bs, (New-Object System.Text.UTF8Encoding($false)))

# The shipped locale JSON, so the assertions exercise the real messages.
Remove-Item -Recurse -Force "$here\entry-locales" -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path "$here\entry-locales" | Out-Null
Copy-Item "$root\entry\src\main\resources\rawfile\i18n\*.json" "$here\entry-locales\" -Force

# --- Compile and run --------------------------------------------------------
Push-Location $here
try {
    node $tsc --target ES2020 --module commonjs --moduleResolution node `
        --experimentalDecorators --skipLibCheck --outDir out harness.ts
    if ($LASTEXITCODE -ne 0) { Write-Error "tsc failed with exit code $LASTEXITCODE" }

    # Native stderr (the harness logs expected parse failures) must not be
    # treated as a terminating error by the caller's ErrorActionPreference.
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    node out/harness.js
    $code = $LASTEXITCODE
    $ErrorActionPreference = $previousPreference
} finally {
    Pop-Location
}

if ($code -ne 0) {
    Write-Host "Verification FAILED" -ForegroundColor Red
    exit $code
}
Write-Host "Verification passed" -ForegroundColor Green
