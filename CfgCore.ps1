# ============================================================
#  CfgCore.ps1 - Agents Cfg Manager 共用核心函式
#  CLI (Agents-Cfg-Manager.ps1) 與 Web (Agents-Cfg-Manager-Web.ps1) 共用同一套邏輯
#  相容 PowerShell 5.1 與 7.x
# ============================================================

if (-not ('System.IO.Compression.ZipFile' -as [type])) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
}
if (-not ('System.IO.Compression.ZipArchiveMode' -as [type])) {
    Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
}

$script:OcfToolVersion = '1.2.2'
$script:OcfPrefix      = 'files/'
$script:OcfRoot        = $PSScriptRoot

# ---------- 資料目錄（TOOL-SPEC 第 6 節）：-DataDir > DEVTOOLBOX_DATA > %LOCALAPPDATA%\DevToolbox\<id> ----------
# 舊版資料放在工具資料夾（profiles\、job-history.jsonl、packs\），第一次啟動時複製到新位置（不刪舊檔）。
$script:OcfDataDir = $null

function Initialize-OcfData([string]$Override) {
    $base = if ($env:DEVTOOLBOX_DATA) { $env:DEVTOOLBOX_DATA }
            elseif ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'DevToolbox' }
            else { Join-Path $env:TEMP 'DevToolbox' }
    $dir = if ($Override) { [System.IO.Path]::GetFullPath($Override) } else { Join-Path $base 'agents-cfg-manager' }
    # v1.2.0 改名：舊 id 的資料夾（opencode-cfg-manager）在新資料夾不存在時整份複製過來，舊資料夾保留不刪
    if (-not $Override -and -not (Test-Path -LiteralPath $dir)) {
        $renamed = Join-Path $base 'opencode-cfg-manager'
        if (Test-Path -LiteralPath $renamed) { Copy-Item -LiteralPath $renamed -Destination $dir -Recurse }
    }
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $profiles = Join-Path $dir 'profiles'
    if ((Test-Path -LiteralPath $profiles) -ne $true) {
        $legacy = Join-Path $script:OcfRoot 'profiles'
        if (Test-Path -LiteralPath $legacy) { Copy-Item -LiteralPath $legacy -Destination $profiles -Recurse }
        else { New-Item -ItemType Directory -Path $profiles -Force | Out-Null }
    }
    $hist = Join-Path $dir 'history.jsonl'
    if (-not (Test-Path -LiteralPath $hist)) {
        $legacyHist = Join-Path $script:OcfRoot 'job-history.jsonl'
        if (Test-Path -LiteralPath $legacyHist) { Copy-Item -LiteralPath $legacyHist -Destination $hist }
    }
    $script:OcfDataDir    = $dir
    $script:OcfProfileDir = $profiles
    $script:OcfHistoryFile = $hist
    $dir
}
Initialize-OcfData | Out-Null

# ---------- 基本路徑 ----------

function Get-OcfGlobalConfigRoot { Join-Path $env:USERPROFILE '.config\opencode' }
function Get-OcfShareRoot        { Join-Path $env:USERPROFILE '.local\share\opencode' }
function Get-OcfPacksDir {
    $d = Join-Path $script:OcfDataDir 'packs'
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    $d
}
function Get-OcfSuggestedSourceRoot {
    $last = Get-OcfLastProfile
    if ($last -and $last.sourceRoot -and (Test-Path -LiteralPath $last.sourceRoot)) { return $last.sourceRoot }
    $env:USERPROFILE
}

# ---------- 預設範圍 ----------

function Get-OcfDefaultItems {
    @(
        [pscustomobject]@{ path='opencode.json';  enabled=$true; exclude=@() }
        [pscustomobject]@{ path='opencode.jsonc'; enabled=$true; exclude=@() }
        [pscustomobject]@{ path='AGENTS.md';      enabled=$true; exclude=@() }
        [pscustomobject]@{ path='Ai-Data';        enabled=$true; exclude=@() }
        [pscustomobject]@{ path='.opencode';      enabled=$true; exclude=@() }
    )
}

function Get-OcfGlobalItems {
    @(
        [pscustomobject]@{ path='opencode.jsonc'; enabled=$true; exclude=@() }
        [pscustomobject]@{ path='opencode.json';  enabled=$true; exclude=@() }
        [pscustomobject]@{ path='cli.json';       enabled=$true; exclude=@() }
        [pscustomobject]@{ path='service.json';   enabled=$true; exclude=@() }
        [pscustomobject]@{ path='package.json';   enabled=$true; exclude=@() }
        [pscustomobject]@{ path='skills';         enabled=$true; exclude=@() }
        [pscustomobject]@{ path='skill';          enabled=$true; exclude=@() }
        [pscustomobject]@{ path='agents';         enabled=$true; exclude=@() }
        [pscustomobject]@{ path='agent';          enabled=$true; exclude=@() }
        [pscustomobject]@{ path='commands';       enabled=$true; exclude=@() }
        [pscustomobject]@{ path='command';        enabled=$true; exclude=@() }
        [pscustomobject]@{ path='modes';          enabled=$true; exclude=@() }
        [pscustomobject]@{ path='plugins';        enabled=$true; exclude=@() }
    )
}

function Get-OcfAllItems {
    @(Get-OcfDefaultItems) + @(Get-OcfGlobalItems | ForEach-Object {
        [pscustomobject]@{ path=$_.path; enabled=$false; exclude=$_.exclude; base=(Get-OcfGlobalConfigRoot) }
    })
}

function Get-OcfItemsByPreset {
    param([string]$Preset)
    switch ($Preset) {
        'project' { @(Get-OcfDefaultItems) }
        'global'  { @(Get-OcfGlobalItems) }
        'all'     { @(Get-OcfAllItems) }
        default   { @(Get-OcfDefaultItems) }
    }
}

# ---------- 小工具 ----------

function Write-OcfText {
    param([string]$Path, [string]$Text)
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}
function Read-OcfText {
    param([string]$Path)
    [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}
function ConvertTo-OcfJson { param($Object,[int]$Depth=12) (ConvertTo-Json -InputObject $Object -Depth $Depth -Compress:$false) }

function Format-OcfBytes {
    param([object]$Bytes)
    if ($null -eq $Bytes) { return '-' }
    $b = [double]$Bytes
    if ($b -lt 1KB)  { return "$b B" }
    if ($b -lt 1MB)  { return ('{0:N1} KB' -f ($b/1KB)) }
    if ($b -lt 1GB)  { return ('{0:N1} MB' -f ($b/1MB)) }
    ('{0:N2} GB' -f ($b/1GB))
}

function Convert-OcfItem {
    param($Item)
    $p = ''; $en = $true; $ex = @(); $base = ''
    if ($Item -is [string]) { $p = $Item }
    elseif ($null -ne $Item) {
        if ($null -ne $Item.path)    { $p = [string]$Item.path }
        if ($null -ne $Item.enabled) { $en = [bool]$Item.enabled }
        if ($null -ne $Item.exclude) { $ex = @($Item.exclude | Where-Object { $_ }) }
        if ($null -ne $Item.base)    { $base = [string]$Item.base }
    }
    [pscustomobject]@{ path=$p; enabled=$en; exclude=@($ex); base=$base }
}

function Test-OcfSkipPath {
    param([string]$Rel)
    $segs = $Rel -split '[\\/]'
    foreach ($s in $segs) { if ($s -ieq 'node_modules') { return $true } }
    $leaf = $segs[$segs.Count-1]
    foreach ($n in @('opencode.db','opencode.db-shm','opencode.db-wal')) { if ($leaf -ieq $n) { return $true } }
    return $false
}

function Test-OcfMatchExclude {
    param([string]$Name, [string[]]$Patterns)
    foreach ($pat in @($Patterns)) { if ($Name -like $pat) { return $true } }
    return $false
}

function Test-OcfInside {
    param([string]$Inner, [string]$Outer)
    $n1 = (Get-OcfFullN $Inner); $n2 = (Get-OcfFullN $Outer)
    if (-not $n1 -or -not $n2) { return $false }
    if ($n1 -ieq $n2) { return $true }
    return $n1.ToLowerInvariant().StartsWith($n2.ToLowerInvariant() + '\')
}
function Get-OcfFullN {
    param([string]$Path)
    if (-not $Path) { return $null }
    try {
        if (Test-Path -LiteralPath $Path) { return (Get-Item -LiteralPath $Path -Force).FullName.TrimEnd('\') }
        return [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    } catch { return $null }
}

function New-OcfTargetRoot {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
    (Get-Item -LiteralPath $Path -Force).FullName.TrimEnd('\')
}

function Get-OcfComposeZipPath {
    param([string]$ZipDir, [string]$NamePattern, [string]$Label, [string]$OutZip)
    if ($OutZip) { return [System.IO.Path]::GetFullPath($OutZip) }
    if (-not $ZipDir) { $ZipDir = Get-OcfPacksDir }
    if (-not $Label)  { $Label = 'project' }
    if (-not $NamePattern) { $NamePattern = 'agents-cfg_<ts>_<label>.zip' }
    $name = $NamePattern.Replace('<ts>', (Get-Date -Format 'yyyyMMdd-HHmmss')).Replace('<label>', $Label)
    [System.IO.Path]::GetFullPath((Join-Path $ZipDir $name))
}

# ---------- 解析項目 → 實際檔案清單 ----------

function Resolve-OcfItems {
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [AllowEmptyCollection()][object[]]$Items
    )
    if (-not (Test-Path -LiteralPath $SourceRoot)) { throw "來源根目錄不存在: $SourceRoot" }
    $rootFull = (Get-Item -LiteralPath $SourceRoot -Force).FullName.TrimEnd('\')
    $rootLen  = $rootFull.Length

    $seen  = @{}
    $files = New-Object System.Collections.Generic.List[object]
    $stats = New-Object System.Collections.Generic.List[object]

    foreach ($raw in @($Items)) {
        $it = Convert-OcfItem -Item $raw
        if (-not $it.path) { continue }
        $stat = [pscustomobject]@{ Path=$it.path; Found=$false; Count=0; Bytes=[long]0; Error=$null }
        if (-not $it.enabled) { $stat.Error = '(未啟用)'; $stats.Add($stat); continue }

        # 指定 base 時（all preset 的全域項目）改從該根解析，並改寫相對路徑
        $srcBase = $rootFull; $srcBaseLen = $rootLen; $relOverride = $null
        if ($it.base) {
            if (-not (Test-Path -LiteralPath $it.base)) { $stat.Error = "base 不存在: $($it.base)"; $stats.Add($stat); continue }
            $srcBase = (Get-Item -LiteralPath $it.base -Force).FullName.TrimEnd('\')
            $srcBaseLen = $srcBase.Length
            $relOverride = '~\.config\opencode'
        }

        $safeBase = $srcBase.Replace('[','`[').Replace(']','`]')
        $pattern  = Join-Path $safeBase $it.path
        $targets  = @(Get-Item -Path $pattern -Force -ErrorAction SilentlyContinue)
        if ($targets.Count -eq 0) { $stat.Error = '找不到（略過）'; $stats.Add($stat); continue }
        $stat.Found = $true

        foreach ($t in $targets) {
            $collect = New-Object System.Collections.Generic.List[object]
            if ($t.PSIsContainer) {
                foreach ($f in (Get-ChildItem -LiteralPath $t.FullName -Recurse -Force -ErrorAction SilentlyContinue)) {
                    if ($f.PSIsContainer) { continue }
                    if (Test-OcfMatchExclude $f.Name $it.exclude) { continue }
                    $collect.Add($f)
                }
            } else {
                if (-not (Test-OcfMatchExclude $t.Name $it.exclude)) { $collect.Add($t) }
            }
            foreach ($f in $collect) {
                $rel = if ($relOverride) { Join-Path $relOverride $f.FullName.Substring($srcBaseLen+1) } else { $f.FullName.Substring($srcBaseLen+1) }
                if (Test-OcfSkipPath $rel) { continue }
                $key = $rel.ToLowerInvariant()
                if ($seen.ContainsKey($key)) { continue }
                $seen[$key] = $true
                $files.Add([pscustomobject]@{ Rel=$rel; Full=$f.FullName; Length=$f.Length })
                $stat.Count++; $stat.Bytes += $f.Length
            }
        }
        $stats.Add($stat)
    }

    $total = [long]0; foreach ($f in $files) { $total += $f.Length }
    [pscustomobject]@{
        SourceRoot = $rootFull
        Files      = $files.ToArray()
        Items      = $stats.ToArray()
        Count      = $files.Count
        TotalBytes = $total
    }
}

# ---------- 打包 ----------

function Pack-Ocf {
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [string]$OutZip,
        [string]$ZipDir,
        [string]$NamePattern,
        [AllowEmptyCollection()][object[]]$Items,
        [string]$Label = 'project',
        [switch]$IncludeAuth,
        [switch]$DryRun
    )
    $resolved = Resolve-OcfItems -SourceRoot $SourceRoot -Items $Items

    # 選擇性收錄 auth.json（放在 .share\ 下，還原時可手動搬回 ~/.local/share/opencode）
    $authFile = $null
    if ($IncludeAuth) {
        $authPath = Join-Path (Get-OcfShareRoot) 'auth.json'
        if (Test-Path -LiteralPath $authPath) {
            $ai = Get-Item -LiteralPath $authPath -Force
            $authFile = [pscustomobject]@{ Rel='.share\auth.json'; Full=$ai.FullName; Length=$ai.Length }
        } else { Write-Warning "找不到 auth.json（$authPath），已略過" }
    }

    $allFiles = @($resolved.Files)
    if ($authFile) { $allFiles += $authFile }

    if ($DryRun) {
        return [pscustomobject]@{
            DryRun=$true; SourceRoot=$resolved.SourceRoot
            Items=$resolved.Items; Files=$allFiles
            Count=$allFiles.Count; TotalBytes=(($allFiles | Measure-Object -Property Length -Sum).Sum)
            ZipOut=(Get-OcfComposeZipPath -ZipDir $ZipDir -NamePattern $NamePattern -Label $Label -OutZip $OutZip)
        }
    }

    if ($allFiles.Count -eq 0) { throw '沒有可打包的檔案，請確認範圍設定' }
    $zipPath = Get-OcfComposeZipPath -ZipDir $ZipDir -NamePattern $NamePattern -Label $Label -OutZip $OutZip
    $zipParent = Split-Path -Parent $zipPath
    if ($zipParent -and -not (Test-Path -LiteralPath $zipParent)) { New-Item -ItemType Directory -Path $zipParent -Force | Out-Null }
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }

    $manifest = [ordered]@{
        tool        = 'agents-cfg-manager'
        version     = $script:OcfToolVersion
        created     = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        sourceRoot  = $resolved.SourceRoot
        label       = $Label
        includeAuth = [bool]$IncludeAuth
        fileCount   = $allFiles.Count
        totalBytes  = (($allFiles | Measure-Object -Property Length -Sum).Sum)
        files       = @($allFiles | ForEach-Object { $_.Rel } | Sort-Object)
    }

    $failed = New-Object System.Collections.Generic.List[string]
    $zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        $me = $zip.CreateEntry('manifest.json')
        $ms = $me.Open()
        $mb = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-OcfJson $manifest))
        $ms.Write($mb, 0, $mb.Length); $ms.Dispose()

        foreach ($f in $allFiles) {
            $entryName = $script:OcfPrefix + $f.Rel.Replace('\','/')
            try {
                [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f.Full, $entryName) | Out-Null
            } catch {
                $failed.Add("$($f.Rel): $($_.Exception.Message)")
            }
        }
    } finally { $zip.Dispose() }

    if ($failed.Count -gt 0 -and $failed.Count -eq $allFiles.Count) { throw "打包全部失敗，第一筆: $($failed[0])" }

    [pscustomobject]@{
        DryRun=$false; Zip=$zipPath
        Count=($allFiles.Count - $failed.Count); Skipped=$failed.Count
        SourceBytes=(($allFiles | Measure-Object -Property Length -Sum).Sum)
        ZipBytes=(Get-Item -LiteralPath $zipPath).Length
        Failures=$failed.ToArray()
    }
}

# ---------- 讀 zip ----------

function Read-OcfZip {
    param([Parameter(Mandatory)][string]$Zip)
    if (-not (Test-Path -LiteralPath $Zip)) { throw "Zip 檔案不存在: $Zip" }
    $z = [System.IO.Compression.ZipFile]::OpenRead((Get-OcfFullN $Zip))
    try {
        $manifest = $null
        $me = $z.GetEntry('manifest.json')
        if ($me) {
            $sr = New-Object System.IO.StreamReader($me.Open(), [System.Text.Encoding]::UTF8)
            try { $manifest = ConvertFrom-Json $sr.ReadToEnd() } finally { $sr.Dispose() }
        }
        $files = @($z.Entries | Where-Object { $_.FullName.StartsWith($script:OcfPrefix) -and -not $_.FullName.EndsWith('/') } |
            ForEach-Object { [pscustomobject]@{ Rel=$_.FullName.Substring($script:OcfPrefix.Length).Replace('/','\'); Length=$_.Length } })
    } finally { $z.Dispose() }
    [pscustomobject]@{
        Zip=$Zip; Manifest=$manifest; Count=$files.Count
        Bytes=(($files | Measure-Object -Property Length -Sum).Sum)
        Files=$files
    }
}

# ---------- 解壓 ----------

function Expand-Ocf {
    param(
        [Parameter(Mandatory)][string]$Zip,
        [Parameter(Mandatory)][string]$TargetRoot,
        [switch]$DryRun,
        [switch]$NoBackup
    )
    $data = Read-OcfZip -Zip $Zip
    if (-not $data.Manifest) { throw '此 zip 沒有 manifest.json，不是本工具產生的壓縮包' }
    $rootFull = New-OcfTargetRoot -Path $TargetRoot

    $z = [System.IO.Compression.ZipFile]::OpenRead((Get-OcfFullN $Zip))
    try {
        $plan = New-Object System.Collections.Generic.List[object]
        $new = 0; $over = 0; $bad = 0
        foreach ($fe in $data.Files) {
            if ($fe.Rel -match '(^|[\\/])\.\.([\\/]|$)') { $bad++; continue }
            $dest = Join-Path $rootFull $fe.Rel
            $entry = $z.GetEntry($script:OcfPrefix + $fe.Rel.Replace('\','/'))
            if (-not $entry) { continue }
            $exists = Test-Path -LiteralPath $dest
            if ($exists) { $over++ } else { $new++ }
            $plan.Add([pscustomobject]@{ Rel=$fe.Rel; Entry=$entry; Dest=$dest; Exists=$exists })
        }

        if ($DryRun) {
            return [pscustomobject]@{
                DryRun=$true; TargetRoot=$rootFull; Manifest=$data.Manifest
                Count=$plan.Count; New=$new; Overwrite=$over; UnsafeSkipped=$bad
                OverwriteList=@($plan | Where-Object { $_.Exists } | ForEach-Object { $_.Rel } | Select-Object -First 200)
            }
        }

        $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backupRoot = $null; $backed = 0; $written = 0
        $failed = New-Object System.Collections.Generic.List[string]
        foreach ($p in $plan) {
            $destDir = Split-Path -Parent $p.Dest
            if ($destDir -and -not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
            try {
                if ($p.Exists -and -not $NoBackup) {
                    if (-not $backupRoot) { $backupRoot = Join-Path $rootFull ("_backup\restore-$ts") }
                    $bp = Join-Path $backupRoot $p.Rel
                    $bpd = Split-Path -Parent $bp
                    if ($bpd -and -not (Test-Path -LiteralPath $bpd)) { New-Item -ItemType Directory -Path $bpd -Force | Out-Null }
                    Move-Item -LiteralPath $p.Dest -Destination $bp -Force
                    $backed++
                }
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($p.Entry, $p.Dest, $true)
                $written++
            } catch { $failed.Add("$($p.Rel): $($_.Exception.Message)") }
        }
    } finally { $z.Dispose() }

    [pscustomobject]@{
        DryRun=$false; TargetRoot=$rootFull; Count=$written
        New=$new; Overwrite=$over; BackedUp=$backed; BackupRoot=$backupRoot; Failures=$failed.ToArray()
    }
}

# ---------- 目錄 → 目錄部署複製 ----------

function Copy-Ocf {
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$TargetRoot,
        [AllowEmptyCollection()][object[]]$Items,
        [switch]$DryRun,
        [switch]$NoBackup
    )
    $srcFull = New-OcfTargetRoot -Path $SourceRoot
    $tgtFull = New-OcfTargetRoot -Path $TargetRoot
    if ($srcFull -ieq $tgtFull) { throw '來源與目標是同一個目錄' }
    if (Test-OcfInside $tgtFull $srcFull) { throw "目標在來源內部，會造成遞迴複製: $tgtFull" }
    if (Test-OcfInside $srcFull $tgtFull) { throw "來源在目標內部，會造成遞迴複製: $srcFull" }

    $resolved = Resolve-OcfItems -SourceRoot $srcFull -Items $Items

    $plan = New-Object System.Collections.Generic.List[object]
    $new = 0; $over = 0
    foreach ($f in $resolved.Files) {
        $dest = Join-Path $tgtFull $f.Rel
        $exists = Test-Path -LiteralPath $dest
        if ($exists) { $over++ } else { $new++ }
        $plan.Add([pscustomobject]@{ Rel=$f.Rel; Src=$f.Full; Dest=$dest; Exists=$exists })
    }

    if ($DryRun) {
        return [pscustomobject]@{
            DryRun=$true; SourceRoot=$srcFull; TargetRoot=$tgtFull
            Items=$resolved.Items; Count=$plan.Count; New=$new; Overwrite=$over
            OverwriteList=@($plan | Where-Object { $_.Exists } | ForEach-Object { $_.Rel } | Select-Object -First 200)
        }
    }

    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupRoot = $null; $backed = 0; $written = 0
    $failed = New-Object System.Collections.Generic.List[string]
    foreach ($p in $plan) {
        $destDir = Split-Path -Parent $p.Dest
        if ($destDir -and -not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        try {
            if ($p.Exists -and -not $NoBackup) {
                if (-not $backupRoot) { $backupRoot = Join-Path $tgtFull ("_backup\deploy-$ts") }
                $bp = Join-Path $backupRoot $p.Rel
                $bpd = Split-Path -Parent $bp
                if ($bpd -and -not (Test-Path -LiteralPath $bpd)) { New-Item -ItemType Directory -Path $bpd -Force | Out-Null }
                Move-Item -LiteralPath $p.Dest -Destination $bp -Force
                $backed++
            }
            [System.IO.File]::Copy($p.Src, $p.Dest, $true)
            $written++
        } catch { $failed.Add("$($p.Rel): $($_.Exception.Message)") }
    }

    [pscustomobject]@{
        DryRun=$false; SourceRoot=$srcFull; TargetRoot=$tgtFull; Count=$written
        New=$new; Overwrite=$over; BackedUp=$backed; BackupRoot=$backupRoot; Failures=$failed.ToArray()
    }
}

# ---------- Profiles ----------

function Get-OcfProfileDir {
    if (-not (Test-Path -LiteralPath $script:OcfProfileDir)) { New-Item -ItemType Directory -Path $script:OcfProfileDir -Force | Out-Null }
    $script:OcfProfileDir
}
function Test-OcfProfileName {
    param([string]$Name)
    if (-not $Name) { return $false }
    if ($Name -match '[\\/:*?"<>|]') { return $false }
    if ($Name -eq '_last') { return $false }
    $true
}
function Get-OcfProfilePath { param([string]$Name) Join-Path (Get-OcfProfileDir) "$Name.json" }

function Get-OcfProfiles {
    $dir = Get-OcfProfileDir
    @(Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne '_last.json' } | ForEach-Object {
            $data = $null
            try { $data = ConvertFrom-Json (Read-OcfText $_.FullName) } catch {}
            [pscustomobject]@{ Name=$_.BaseName; Path=$_.FullName; Updated=$_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'); Data=$data }
        } | Sort-Object Name)
}
function Get-OcfProfile {
    param([string]$Name)
    $p = Get-OcfProfilePath -Name $Name
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    ConvertFrom-Json (Read-OcfText $p)
}
function Save-OcfProfile {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)]$Data)
    if (-not (Test-OcfProfileName $Name)) { throw "設定檔名稱不合法: $Name" }
    Write-OcfText -Path (Get-OcfProfilePath -Name $Name) -Text (ConvertTo-OcfJson $Data)
    [pscustomobject]@{ Name=$Name; Path=(Get-OcfProfilePath -Name $Name) }
}
function Remove-OcfProfile {
    param([Parameter(Mandatory)][string]$Name)
    $p = Get-OcfProfilePath -Name $Name
    if (-not (Test-Path -LiteralPath $p)) { throw "設定檔不存在: $Name" }
    Remove-Item -LiteralPath $p -Force
}
function Get-OcfLastProfile {
    $p = Join-Path $script:OcfProfileDir '_last.json'
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    try { ConvertFrom-Json (Read-OcfText $p) } catch { $null }
}
function Save-OcfLastProfile {
    param([Parameter(Mandatory)]$Data)
    Get-OcfProfileDir | Out-Null
    Write-OcfText -Path (Join-Path $script:OcfProfileDir '_last.json') -Text (ConvertTo-OcfJson $Data)
}

# ---------- 工作歷史 ----------

function Get-OcfHistory {
    param([int]$Limit = 100)
    if (-not (Test-Path -LiteralPath $script:OcfHistoryFile)) { return @() }
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($line in (Get-Content -LiteralPath $script:OcfHistoryFile -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        if (-not $line.Trim()) { continue }
        try { $null = $out.Add((ConvertFrom-Json $line)) } catch {}
    }
    # 檔案本身就是新在前（每次 prepend），不需再反轉
    if ($out.Count -gt $Limit) { return @($out.ToArray())[0..($Limit-1)] }
    @($out.ToArray())
}
function Add-OcfHistory {
    param(
        [Parameter(Mandatory)][string]$Action, [string]$Detail = '',
        [int]$Count = 0, [long]$Bytes = 0, [string]$Status = 'ok',
        [string]$Source = '', [string]$Target = '', [string]$Profile = '', [string]$Cli = ''
    )
    $entry = [ordered]@{
        id=[guid]::NewGuid().ToString('N').Substring(0,12)
        time=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        action=$Action; detail=$Detail; count=$Count; bytes=$Bytes; status=$Status
        source=$Source; target=$Target; profile=$Profile; cli=$Cli
    }
    $lines = @()
    if (Test-Path -LiteralPath $script:OcfHistoryFile) {
        $lines = @(Get-Content -LiteralPath $script:OcfHistoryFile -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_.Trim() })
    }
    $lines = @((ConvertTo-Json -InputObject $entry -Depth 6 -Compress)) + $lines
    if ($lines.Count -gt 100) { $lines = $lines[0..99] }
    Write-OcfText -Path $script:OcfHistoryFile -Text (($lines -join "`r`n") + "`r`n")
    [pscustomobject]$entry
}
function Remove-OcfHistory {
    param([Parameter(Mandatory)][string]$Id)
    if (-not (Test-Path -LiteralPath $script:OcfHistoryFile)) { return $false }
    $lines = @(Get-Content -LiteralPath $script:OcfHistoryFile -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_.Trim() })
    $keep = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
        $keepOn = $true
        try { $o = ConvertFrom-Json $line; if ($o.id -eq $Id) { $keepOn = $false } } catch {}
        if ($keepOn) { $keep.Add($line) }
    }
    if ($keep.Count -eq 0) { Remove-Item -LiteralPath $script:OcfHistoryFile -Force; return $true }
    Write-OcfText -Path $script:OcfHistoryFile -Text (($keep -join "`r`n") + "`r`n")
    $true
}
function Clear-OcfHistory {
    if (Test-Path -LiteralPath $script:OcfHistoryFile) { Remove-Item -LiteralPath $script:OcfHistoryFile -Force }
}
