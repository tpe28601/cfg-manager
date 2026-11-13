# ============================================================
#  Agents-Cfg-Manager-Web.ps1 - OpenCode 設定檔複製工具（本機 Web 控制台）
#  純 PowerShell HttpListener，僅綁 127.0.0.1
# 用法:
#   .\Agents-Cfg-Manager-Web.ps1 [-Port 8712] [-OpenBrowser] [-ParentPid <pid>] [-DataDir <路徑>] [-HubOrigin <url>]
#   -Port       指定 port；沒指定時從 8712 往上找（最多 +20），都不行就請系統配一個空的 port
#   -HubOrigin  Hub 的實際網址（例如 http://127.0.0.1:8700），允許它嵌入本頁
#   -ParentPid  父行程（例如 Dev-Toolbox Hub）結束時自動關閉
#   -DataDir    覆寫資料夾（預設 %LOCALAPPDATA%\DevToolbox\agents-cfg-manager）
# 啟動成功時 stdout 印出一行：READY http://127.0.0.1:<port>（TOOL-SPEC 第 5 節）
#   Ctrl+C 停止，或呼叫 POST /api/shutdown
# ============================================================
param(
    [int]$Port = 8712,
    [switch]$OpenBrowser,
    [int]$ParentPid = 0,
    [string]$DataDir,
    [string]$HubOrigin
)
$script:PortExplicit = $PSBoundParameters.ContainsKey('Port')

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'CfgCore.ps1')
if ($DataDir) { Initialize-OcfData -Override $DataDir | Out-Null }
$script:HubOrigins = @('http://127.0.0.1:8700', 'http://localhost:8700')
if ($HubOrigin -match '^http://(127\.0\.0\.1|localhost):(\d{1,5})$') {
    $script:HubOrigins = @("http://127.0.0.1:$($matches[2])", "http://localhost:$($matches[2])")
}
$script:StartedAt = Get-Date
$script:UiDir = Join-Path $PSScriptRoot 'ui'   # ui-kit.css 複本由 Dev-Toolbox/ui-kit/Sync-UiKit.ps1 同步到 ui\

# ---------- 回應工具 ----------

function Send-OcfBytes {
    param($Ctx, [int]$Code, [byte[]]$Bytes, [string]$ContentType)
    $Ctx.Response.StatusCode = $Code
    $Ctx.Response.ContentType = $ContentType
    # 安全標頭（TOOL-SPEC 第 5 節）：禁止 MIME 猜測、只允許自己與 Hub 嵌入、不送 Referer
    $Ctx.Response.Headers.Add('Cache-Control', 'no-store')
    $Ctx.Response.Headers.Add('X-Content-Type-Options', 'nosniff')
    $Ctx.Response.Headers.Add('Content-Security-Policy', "frame-ancestors 'self' $($script:HubOrigins -join ' ')")
    $Ctx.Response.Headers.Add('Referrer-Policy', 'no-referrer')
    $Ctx.Response.ContentLength64 = $Bytes.Length
    $Ctx.Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
    $Ctx.Response.OutputStream.Close()
}
function Send-OcfJson {
    param($Ctx, [int]$Code, $Object)
    $json = ConvertTo-Json -InputObject $Object -Depth 14
    Send-OcfBytes -Ctx $Ctx -Code $Code -Bytes ([System.Text.Encoding]::UTF8.GetBytes($json)) -ContentType 'application/json; charset=utf-8'
}
# 錯誤格式（TOOL-SPEC）：{ ok:false, error:{ code, message, detail } }
function Send-OcfError {
    param($Ctx, [int]$Code, [string]$Message, [string]$ErrCode = 'INTERNAL')
    Send-OcfJson $Ctx $Code ([pscustomobject]@{ ok = $false; error = [pscustomobject]@{ code = $ErrCode; message = $Message; detail = $null } })
}

# 安全檢查（TOOL-SPEC 第 5 節）。回傳 $null 放行，否則已自行回覆。
function Test-OcfRequestAllowed {
    param($Ctx)
    $port = $script:BoundPort
    $hostHdr = ([string]$Ctx.Request.Headers['Host']).ToLowerInvariant()
    if ($hostHdr -notin @("127.0.0.1:$port", "localhost:$port")) {
        Send-OcfError $Ctx 403 "不允許的 Host：$hostHdr" 'FORBIDDEN_HOST'; return $false
    }
    if ($Ctx.Request.HttpMethod -eq 'GET' -or $Ctx.Request.HttpMethod -eq 'HEAD') { return $true }
    if ($Ctx.Request.HttpMethod -ne 'POST') {
        Send-OcfError $Ctx 405 "不支援的方法：$($Ctx.Request.HttpMethod)" 'METHOD_NOT_ALLOWED'; return $false
    }
    if (([string]$Ctx.Request.Headers['X-Toolbox-Request']) -ne '1') {
        Send-OcfError $Ctx 403 '缺少 X-Toolbox-Request 標頭' 'MISSING_TOOLBOX_HEADER'; return $false
    }
    $origin = ([string]$Ctx.Request.Headers['Origin']).ToLowerInvariant()
    if ($origin) {
        $allowed = @("http://127.0.0.1:$port", "http://localhost:$port") + $script:HubOrigins
        if ($origin -notin $allowed) {
            Send-OcfError $Ctx 403 "不允許的來源：$origin" 'FORBIDDEN_ORIGIN'; return $false
        }
    }
    if (-not ([string]$Ctx.Request.ContentType).ToLowerInvariant().StartsWith('application/json')) {
        Send-OcfError $Ctx 415 'Content-Type 必須是 application/json' 'UNSUPPORTED_MEDIA_TYPE'; return $false
    }
    if ($Ctx.Request.ContentLength64 -gt 1MB) {
        Send-OcfError $Ctx 413 '請求內容超過 1 MB' 'PAYLOAD_TOO_LARGE'; return $false
    }
    return $true
}

function Read-OcfBody {
    param($Ctx)
    $sr = New-Object System.IO.StreamReader($Ctx.Request.InputStream, [System.Text.Encoding]::UTF8)
    $text = $sr.ReadToEnd(); $sr.Dispose()
    if (-not $text.Trim()) { return [pscustomobject]@{} }
    ConvertFrom-Json $text
}

function Get-OcfUiFile {
    param([string]$Name)
    if ($Name -notmatch '^[\w\.\-]+$') { return $null }
    $p = Join-Path $script:UiDir $Name
    if (Test-Path -LiteralPath $p -PathType Leaf) { return $p }
    $null
}
function Get-OcfMime {
    param([string]$Path)
    switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        '.html' { 'text/html; charset=utf-8' }
        '.js'   { 'application/javascript; charset=utf-8' }
        '.css'  { 'text/css; charset=utf-8' }
        '.json' { 'application/json; charset=utf-8' }
        '.svg'  { 'image/svg+xml' }
        '.png'  { 'image/png' }
        default { 'application/octet-stream' }
    }
}

# ---------- API ----------

# Resolve-OcfItems 的統計物件屬性是大寫開頭，統一轉小寫給前端
function ConvertTo-OcfStatsLower {
    param($Stats)
    @(@($Stats) | ForEach-Object {
        [pscustomobject]@{ path=$_.Path; found=$_.Found; count=$_.Count; bytes=$_.Bytes; error=$_.Error }
    })
}

function Get-OcfBrowse {
    # 統一瀏覽 API（ui-kit tb-dirpicker 契約，與 Git Ref Manager /api/browse 同格式）：
    #   { current, parent, items:[{name,path,hasGit,isFile?}], truncated } / 掃描回 { repos }
    param([string]$Path, [switch]$Scan, [int]$Depth = 2, [int]$Limit = 50,
          [switch]$Files, [string[]]$Extensions)
    $skipped = @('$RECYCLE.BIN','System Volume Information','Windows','Program Files','Program Files (x86)','ProgramData','node_modules','.git','Build','Conf','AppData')
    if ($Scan) {
        $found = New-Object 'System.Collections.Generic.List[object]'
        $stack = New-Object 'System.Collections.Generic.Stack[tuple[string,int]]'
        $rootP = try { (Get-Item -LiteralPath $Path).FullName } catch { throw "無效路徑: $Path" }
        $stack.Push([tuple[string,int]]::new($rootP, 0))
        while ($stack.Count -gt 0 -and $found.Count -lt $Limit) {
            $cur = $stack.Pop()
            foreach ($d in @(Get-ChildItem -LiteralPath $cur.Item1 -Directory -Force -ErrorAction SilentlyContinue)) {
                if ($found.Count -ge $Limit) { break }
                if ($skipped -contains $d.Name) { continue }
                if (Test-Path -LiteralPath (Join-Path $d.FullName '.git')) {
                    $found.Add([pscustomobject]@{ path = $d.FullName; name = $d.Name }) | Out-Null
                }
                if ($cur.Item2 -lt $Depth) { $stack.Push([tuple[string,int]]::new($d.FullName, $cur.Item2 + 1)) }
            }
        }
        return [pscustomobject]@{ repos = @($found.ToArray()) }
    }
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $drives = @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | ForEach-Object {
            [pscustomobject]@{ name = $_.Root; path = $_.Root; hasGit = $false }
        })
        return [pscustomobject]@{ current = ''; parent = $null; items = $drives; truncated = $false }
    }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item) { throw "路徑不存在: $Path" }
    $dir = if ($item.PSIsContainer) { $item } else { $item.Parent }
    if (-not $dir) { throw "已在根層: $Path" }
    $items = @()
    $trunc = $false
    $kids = @(Get-ChildItem -LiteralPath $dir.FullName -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin $skipped } | Sort-Object Name)
    foreach ($d in @($kids | Select-Object -First 500)) {
        $items += [pscustomobject]@{
            name   = $d.Name
            path   = $d.FullName
            hasGit = (Test-Path -LiteralPath (Join-Path $d.FullName '.git'))
        }
    }
    if (@($kids).Count -gt 500) { $trunc = $true }
    if ($Files) {
        $fileQ = @(Get-ChildItem -LiteralPath $dir.FullName -File -Force -ErrorAction SilentlyContinue)
        if ($Extensions -and @($Extensions).Count) {
            $fileQ = @($fileQ | Where-Object { $Extensions -contains $_.Extension.ToLower() })
        }
        foreach ($fl in @($fileQ | Sort-Object Name | Select-Object -First 300)) {
            $items += [pscustomobject]@{ name = $fl.Name; path = $fl.FullName; hasGit = $false; isFile = $true }
        }
    }
    $parent = $null
    if ($dir.Parent -and $dir.Parent.FullName -ne $dir.FullName) { $parent = $dir.Parent.FullName }
    [pscustomobject]@{ current = $dir.FullName; parent = $parent; items = @($items); truncated = $trunc }
}

function Invoke-OcfRoute {
    param($Ctx)
    if (-not (Test-OcfRequestAllowed $Ctx)) { return }
    $path = $Ctx.Request.Url.AbsolutePath
    $method = $Ctx.Request.HttpMethod

    # ---- 靜態 ----
    if ($method -eq 'GET') {
        if ($path -in @('/','/index.html')) {
            $f = Get-OcfUiFile 'index.html'
            if ($f) { Send-OcfBytes $Ctx 200 ([System.IO.File]::ReadAllBytes($f)) (Get-OcfMime $f); return }
            Send-OcfError $Ctx 500 'ui\index.html 不存在'; return
        }
        $f = Get-OcfUiFile $path.TrimStart('/')
        if ($f) { Send-OcfBytes $Ctx 200 ([System.IO.File]::ReadAllBytes($f)) (Get-OcfMime $f); return }
        if ($path -eq '/favicon.ico') { Send-OcfBytes $Ctx 204 ([byte[]]@()) 'image/x-icon'; return }
    }

    if (-not $path.StartsWith('/api/')) { Send-OcfError $Ctx 404 "未知路徑: $path" 'NOT_FOUND'; return }

    # ---- API ----
    switch ("$method $path") {
        'POST /api/standalone-update' {
            if ($ParentPid -gt 0) { Send-OcfError $Ctx 403 '請從 Hub 更新工具。' 'MANAGED_BY_HUB'; return }
            $body = Read-OcfBody $Ctx
            $updater = Join-Path $PSScriptRoot 'Standalone-Update.ps1'
            if ($body.action -eq 'check') {
                $result = & $updater -Action Check | ConvertFrom-Json
                Send-OcfJson $Ctx 200 $result
                return
            }
            if ($body.action -ne 'open' -or [string]$body.version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') {
                Send-OcfError $Ctx 400 '更新請求格式不正確。' 'BAD_ARGS'
                return
            }
            & $updater -Action Open -Version $body.version
            Send-OcfJson $Ctx 200 @{ ok = $true }
            return
        }
        'GET /api/health' {
            Send-OcfJson $Ctx 200 ([ordered]@{
                ok = $true; id = 'agents-cfg-manager'; version = $script:OcfToolVersion
                pid = $PID; port = $script:BoundPort; uptimeSec = [int]((Get-Date) - $script:StartedAt).TotalSeconds
            })
            return
        }
        'GET /api/info' {
            Send-OcfJson $Ctx 200 ([ordered]@{
                ok = $true
                tool = [ordered]@{
                    id = 'agents-cfg-manager'; name = 'Agents Cfg Manager'
                    version = $script:OcfToolVersion; description = 'AI agent 設定檔打包／部署工具'
                }
                dataDir = $script:OcfDataDir
            })
            return
        }
        'GET /api/state' {
            $last = Get-OcfLastProfile
            if ($last -and $last.sourceRoot -and -not (Test-Path -LiteralPath $last.sourceRoot)) { $last.sourceRoot = '' }
            if ($last -and $last.targetRoot -and -not (Test-Path -LiteralPath $last.targetRoot)) { $last.targetRoot = '' }
            Send-OcfJson $Ctx 200 ([ordered]@{
                ok = $true
                port = $script:BoundPort
                time = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
                defaults = [ordered]@{
                    configRoot       = (Get-OcfGlobalConfigRoot)
                    shareRoot        = (Get-OcfShareRoot)
                    suggestedSource  = (Get-OcfSuggestedSourceRoot)
                    zipDir           = (Get-OcfPacksDir)
                }
                last = $last
                profileNames = @(Get-OcfProfiles | ForEach-Object { $_.Name })
            })
            return
        }
        'GET /api/defaults/items' {
            Send-OcfJson $Ctx 200 ([pscustomobject]@{
                project = @(Get-OcfDefaultItems)
                global  = @(Get-OcfGlobalItems)
                all     = @(Get-OcfAllItems)
            })
            return
        }
        'GET /api/browse' {
            $q = [System.Uri]::UnescapeDataString($Ctx.Request.QueryString['path'])
            Send-OcfJson $Ctx 200 (Get-OcfBrowse -Path $q)
            return
        }
        'POST /api/browse' {
            $b = Read-OcfBody $Ctx
            $r = if ($b.scan) {
                # 缺欄位補預設：[int]$null 會轉 0，掃描會回空清單
                $dep = if ($b.depth) { [int]$b.depth } else { 2 }
                $lim = if ($b.limit) { [int]$b.limit } else { 50 }
                Get-OcfBrowse -Path ([string]$b.path) -Scan -Depth $dep -Limit $lim
            } else {
                $ext = @($b.extensions | ForEach-Object { [string]$_ })
                Get-OcfBrowse -Path ([string]$b.path) -Files:([bool]$b.files) -Extensions $ext
            }
            Send-OcfJson $Ctx 200 $r
            return
        }
        'GET /api/profiles' {
            Send-OcfJson $Ctx 200 ([pscustomobject]@{
                profiles = @(Get-OcfProfiles | ForEach-Object { [pscustomobject]@{ name=$_.Name; updated=$_.Updated; data=$_.Data } })
            })
            return
        }
        'GET /api/history' {
            Send-OcfJson $Ctx 200 ([pscustomobject]@{ entries = @(Get-OcfHistory -Limit 100) })
            return
        }
        'GET /api/zip' {
            $zp = [System.Uri]::UnescapeDataString($Ctx.Request.QueryString['path'])
            $info = Read-OcfZip -Zip $zp
            Send-OcfJson $Ctx 200 ([ordered]@{
                zip=$info.Zip; manifest=$info.Manifest; count=$info.Count; bytes=$info.Bytes
                files=@($info.Files | Select-Object -First 300 | ForEach-Object { [pscustomobject]@{ rel=$_.Rel; length=$_.Length } })
                truncated=($info.Count -gt 300)
            })
            return
        }
        'POST /api/items/scan' {
            $b = Read-OcfBody $Ctx
            $r = Resolve-OcfItems -SourceRoot $b.sourceRoot -Items @($b.items)
            Send-OcfJson $Ctx 200 ([ordered]@{
                items = (ConvertTo-OcfStatsLower $r.Items)
                count = $r.Count
                bytes = $r.TotalBytes
                sample = @($r.Files | ForEach-Object { [pscustomobject]@{ rel=$_.Rel; length=$_.Length } } | Select-Object -First 300)
                truncated = ($r.Count -gt 300)
            })
            return
        }
        'POST /api/pack' {
            $b = Read-OcfBody $Ctx
            $zipPath = Get-OcfComposeZipPath -ZipDir $b.zipDir -NamePattern $b.namePattern -Label $b.label -OutZip $b.zipOut
            if ($b.dryRun) {
                $pv = Pack-Ocf -SourceRoot $b.sourceRoot -OutZip $zipPath -Items @($b.items) -Label $b.label -IncludeAuth:([bool]$b.includeAuth) -DryRun
                Send-OcfJson $Ctx 200 ([ordered]@{
                    dryRun=$true; zipOut=$pv.ZipOut; items=(ConvertTo-OcfStatsLower $pv.Items); count=$pv.Count; bytes=$pv.TotalBytes
                })
                return
            }
            $res = Pack-Ocf -SourceRoot $b.sourceRoot -OutZip $zipPath -Items @($b.items) -Label $b.label -IncludeAuth:([bool]$b.includeAuth)
            Save-OcfLastProfile ([ordered]@{ sourceRoot=$b.sourceRoot; label=$b.label; items=@($b.items); includeAuth=[bool]$b.includeAuth; zipDir=$b.zipDir; targetRoot=$b.targetRoot; updated=(Get-Date -Format 's') })
            Add-OcfHistory -Action 'pack' -Detail $b.label -Count $res.Count -Bytes $res.ZipBytes -Source $b.sourceRoot -Target $res.Zip -Cli "Agents-Cfg-Manager.ps1 -Mode pack -SourceRoot '$($b.sourceRoot)' -OutZip '$($res.Zip)'" | Out-Null
            Send-OcfJson $Ctx 200 ([ordered]@{ dryRun=$false; zip=$res.Zip; count=$res.Count; zipBytes=$res.ZipBytes; sourceBytes=$res.SourceBytes; skipped=$res.Skipped })
            return
        }
        'POST /api/unpack' {
            $b = Read-OcfBody $Ctx
            if ($b.dryRun) {
                $pv = Expand-Ocf -Zip $b.zip -TargetRoot $b.targetRoot -DryRun
                Send-OcfJson $Ctx 200 ([ordered]@{ dryRun=$true; targetRoot=$pv.TargetRoot; count=$pv.Count; new=$pv.New; overwrite=$pv.Overwrite; overwriteList=@($pv.OverwriteList) })
                return
            }
            $res = Expand-Ocf -Zip $b.zip -TargetRoot $b.targetRoot -NoBackup:([bool]$b.noBackup)
            Add-OcfHistory -Action 'unpack' -Detail (Split-Path -Leaf $b.zip) -Count $res.Count -Source $b.zip -Target $res.TargetRoot -Cli "Agents-Cfg-Manager.ps1 -Mode unpack -Zip '$($b.zip)' -TargetRoot '$($res.TargetRoot)'" | Out-Null
            Send-OcfJson $Ctx 200 ([ordered]@{ dryRun=$false; targetRoot=$res.TargetRoot; count=$res.Count; new=$res.New; overwrite=$res.Overwrite; backedUp=$res.BackedUp; backupRoot=$res.BackupRoot; failures=@($res.Failures) })
            return
        }
        'POST /api/copy' {
            $b = Read-OcfBody $Ctx
            if ($b.dryRun) {
                $pv = Copy-Ocf -SourceRoot $b.sourceRoot -TargetRoot $b.targetRoot -Items @($b.items) -DryRun
                Send-OcfJson $Ctx 200 ([ordered]@{ dryRun=$true; targetRoot=$pv.TargetRoot; items=(ConvertTo-OcfStatsLower $pv.Items); count=$pv.Count; new=$pv.New; overwrite=$pv.Overwrite; overwriteList=@($pv.OverwriteList) })
                return
            }
            $res = Copy-Ocf -SourceRoot $b.sourceRoot -TargetRoot $b.targetRoot -Items @($b.items) -NoBackup:([bool]$b.noBackup)
            Add-OcfHistory -Action 'copy' -Count $res.Count -Source $b.sourceRoot -Target $res.TargetRoot -Cli "Agents-Cfg-Manager.ps1 -Mode copy -SourceRoot '$($b.sourceRoot)' -TargetRoot '$($res.TargetRoot)'" | Out-Null
            Send-OcfJson $Ctx 200 ([ordered]@{ dryRun=$false; targetRoot=$res.TargetRoot; count=$res.Count; new=$res.New; overwrite=$res.Overwrite; backedUp=$res.BackedUp; backupRoot=$res.BackupRoot; failures=@($res.Failures) })
            return
        }
        'POST /api/profiles/save' {
            $b = Read-OcfBody $Ctx
            $r = Save-OcfProfile -Name $b.name -Data $b.data
            Send-OcfJson $Ctx 200 ([pscustomobject]@{ ok=$true; name=$r.Name; path=$r.Path })
            return
        }
        'POST /api/profiles/load' {
            $b = Read-OcfBody $Ctx
            $d = Get-OcfProfile -Name $b.name
            if (-not $d) { Send-OcfError $Ctx 404 "找不到設定檔: $($b.name)" 'PROFILE_NOT_FOUND'; return }
            Save-OcfLastProfile ([ordered]@{ sourceRoot=$d.sourceRoot; label=$d.label; items=@($d.items); includeAuth=[bool]$d.includeAuth; zipDir=$d.zipDir; targetRoot=$d.targetRoot; updated=(Get-Date -Format 's') })
            Send-OcfJson $Ctx 200 ([pscustomobject]@{ ok=$true; data=$d })
            return
        }
        'POST /api/profiles/delete' {
            $b = Read-OcfBody $Ctx
            Remove-OcfProfile -Name $b.name
            Send-OcfJson $Ctx 200 ([pscustomobject]@{ ok=$true })
            return
        }
        'POST /api/profiles/last' {
            $b = Read-OcfBody $Ctx
            Save-OcfLastProfile -Data $b.data
            Send-OcfJson $Ctx 200 ([pscustomobject]@{ ok=$true })
            return
        }
        'POST /api/history/delete' {
            $b = Read-OcfBody $Ctx
            [void](Remove-OcfHistory -Id $b.id)
            Send-OcfJson $Ctx 200 ([pscustomobject]@{ ok=$true })
            return
        }
        'POST /api/history/clear' {
            Clear-OcfHistory
            Send-OcfJson $Ctx 200 ([pscustomobject]@{ ok=$true })
            return
        }
        'POST /api/shutdown' {
            Send-OcfJson $Ctx 200 ([pscustomobject]@{ ok=$true })
            $script:Shutdown = $true
            return
        }
    }
    Send-OcfError $Ctx 404 "未知 API: $method $path" 'NOT_FOUND'
}

# ---------- 啟動 ----------

$script:Shutdown = $false
$script:BoundPort = 0
$listener = $null
# 明確指定 -Port 時只試那一個；否則從預設 port 往上找（最多 +20），
# 都不行就請系統配一個空的 port（0 代表「向系統要一個」；HttpListener 不能直接綁 0，先用 TcpListener 問）
$tryPorts = if ($script:PortExplicit) { @($Port) } else { @($Port..($Port + 20)) + @(0, 0, 0) }
$portDenied = 0; $portInUse = 0; $lastErr = $null
foreach ($tryPort in $tryPorts) {
    if ($tryPort -eq 0) {
        try {
            $probe = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
            $probe.Start(); $tryPort = ([System.Net.IPEndPoint]$probe.LocalEndpoint).Port; $probe.Stop()
        } catch { $lastErr = $_.Exception.Message; continue }
    }
    $try = New-Object System.Net.HttpListener
    $try.Prefixes.Add("http://127.0.0.1:$tryPort/")
    $try.Prefixes.Add("http://localhost:$tryPort/")
    try {
        $try.Start()
        $listener = $try; $script:BoundPort = $tryPort
        break
    } catch {
        $ex = $_.Exception
        while ($ex -and -not ($ex -is [System.Net.HttpListenerException])) { $ex = $ex.InnerException }
        if ($ex) { switch ([int]$ex.ErrorCode) { 5 { $portDenied++ } 32 { $portInUse++ } 183 { $portInUse++ } } }
        $lastErr = $_.Exception.Message
        $try.Close()
    }
}
if (-not $listener) {
    $why = if ($portDenied -gt 0 -and $portInUse -eq 0) { '存取被拒（port 被 Windows 保留，或缺少 loopback 權限）。可用 netsh interface ipv4 show excludedportrange protocol=tcp 查看' } elseif ($portInUse -gt 0 -and $portDenied -eq 0) { 'port 已被其他程式佔用' } else { $lastErr }
    Write-Host "無法在 127.0.0.1:$($tryPorts[0]) 啟動 HTTP 監聽：$why" -ForegroundColor Red
    if ($script:PortExplicit) { Write-Host '不指定 -Port 時會自動找可用的 port。' -ForegroundColor Gray }
    exit 5
}
# Hub 讀到以 READY 開頭的這一行才算啟動成功（TOOL-SPEC 第 5 節）
[Console]::Out.WriteLine("READY http://127.0.0.1:$script:BoundPort")
[Console]::Out.Flush()

# 父行程監看：-ParentPid 指定的行程結束時自動關閉
$script:ParentProc = $null
if ($ParentPid -gt 0) {
    try { $script:ParentProc = Get-Process -Id $ParentPid -ErrorAction Stop }
    catch { Write-Host "父行程 $ParentPid 不存在，結束。" -ForegroundColor Red; $listener.Close(); exit 1 }
}

$url = "http://127.0.0.1:$script:BoundPort/"
Write-Host '===============================================' -ForegroundColor Cyan
Write-Host " OpenCode 設定檔複製工具 Web 控制台: $url" -ForegroundColor Green
Write-Host ' 只綁定本機 127.0.0.1；停止請按 Ctrl+C 或關閉此視窗' -ForegroundColor DarkGray
Write-Host '===============================================' -ForegroundColor Cyan
if ($OpenBrowser) { Start-Process $url }

try {
    # BeginGetContext + 1 秒輪詢：期間檢查父行程與 Ctrl+C，才能非阻塞收工
    while ($listener.IsListening -and -not $script:Shutdown) {
        $ar = $listener.BeginGetContext($null, $null)
        while (-not $ar.AsyncWaitHandle.WaitOne(1000)) {
            if ($script:ParentProc) {
                $gone = $true
                try { $script:ParentProc.Refresh(); $gone = $script:ParentProc.HasExited } catch { $gone = $true }
                if ($gone) { Write-Host '父行程已結束，自動關閉。' -ForegroundColor Gray; $script:Shutdown = $true; break }
            }
        }
        if ($script:Shutdown) { $ar.AsyncWaitHandle.Close(); break }
        try { $ctx = $listener.EndGetContext($ar) } catch { continue }
        try {
            Invoke-OcfRoute -Ctx $ctx
        } catch {
            try { Send-OcfError $ctx 400 "$($_.Exception.Message)" 'BAD_REQUEST' } catch {}
        }
    }
} finally {
    $listener.Close()
    Write-Host '已停止。' -ForegroundColor DarkGray
}
