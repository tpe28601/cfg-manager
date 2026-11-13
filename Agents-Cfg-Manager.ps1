# ============================================================
#  Agents-Cfg-Manager.ps1 - OpenCode 設定檔複製工具（CLI）
#  選單模式：直接執行，依選單操作
#  Auto 模式：
#    -Mode pack    -SourceRoot <dir> [-OutZip <zip>| -ZipDir <dir>] [-Profile <名>] [-Item a,b,c] [-Label <l>] [-IncludeAuth] [-DryRun] [-Yes]
#    -Mode list    -Zip <zip>
#    -Mode unpack  -Zip <zip> -TargetRoot <dir> [-DryRun] [-NoBackup] [-Yes]
#    -Mode copy    -SourceRoot <dir> -TargetRoot <dir> [-Profile <名>] [-Item a,b,c] [-DryRun] [-NoBackup] [-Yes]
#    -Mode profile [-Action list|show|delete|save] [-Name <設定檔名>]
#  成功 exit 0 / 失敗 exit 1
# ============================================================
param(
    [ValidateSet('','pack','list','unpack','copy','profile')] [string]$Mode = '',
    [string]$SourceRoot, [string]$TargetRoot, [string]$Zip, [string]$OutZip, [string]$ZipDir,
    [string]$Profile = '', [string[]]$Item, [string]$Label = '',
    [ValidateSet('','list','show','delete','save')] [string]$Action = 'list',
    [string]$Name = '',
    [switch]$IncludeAuth, [switch]$DryRun, [switch]$NoBackup, [switch]$Yes,
    [string]$DataDir, [switch]$Version
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
. (Join-Path $PSScriptRoot 'CfgCore.ps1')
if ($DataDir) { Initialize-OcfData -Override $DataDir | Out-Null }
if ($Version) { Write-Output $script:OcfToolVersion; exit 0 }

function Write-Hdr([string]$t)  { Write-Host ''; Write-Host "== $t ==" -ForegroundColor Cyan }
function Write-Ok([string]$t)   { Write-Host $t -ForegroundColor Green }
function Write-Warn2([string]$t){ Write-Host $t -ForegroundColor Yellow }
function Write-Err2([string]$t) { Write-Host $t -ForegroundColor Red }

function Get-WorkingSet {
    $l = Get-OcfLastProfile
    if ($l) {
        [pscustomobject]@{
            sourceRoot  = $l.sourceRoot
            label       = if ($l.label) { $l.label } else { 'project' }
            items       = @(if ($l.items) { @($l.items) } else { @(Get-OcfDefaultItems) })
            includeAuth = [bool]$l.includeAuth
            zipDir      = $l.zipDir
            targetRoot  = $l.targetRoot
        }
    } else {
        [pscustomobject]@{
            sourceRoot=(Get-OcfSuggestedSourceRoot); label='project'
            items=@(Get-OcfDefaultItems); includeAuth=$false; zipDir=''; targetRoot=''
        }
    }
}

function Show-ItemsTable([object[]]$Items, [string]$SourceRoot) {
    $i = 0
    Write-Host ("  {0,3}  {1,-4} {2,-32} {3}" -f '#','於','項目','排除樣式')
    foreach ($raw in $Items) {
        $it = Convert-OcfItem -Item $raw
        $flag = if ($it.enabled) { 'Y' } else { '.' }
        $ex = if ($it.exclude.Count -gt 0) { $it.exclude -join '; ' } else { '-' }
        Write-Host ("  {0,3}  {1,-4} {2,-32} {3}" -f $i, $flag, $it.path, $ex)
        $i++
    }
}

function Show-PackPreview($pv) {
    Write-Host ("  來源: {0}" -f $pv.SourceRoot)
    foreach ($s in $pv.Items) {
        $note = if ($s.Error) { "  <- $($s.Error)" } else { '' }
        Write-Host ("    {0,-32} {1,6} 檔  {2,10}{3}" -f $s.Path, $s.Count, (Format-OcfBytes $s.Bytes), $note)
    }
    Write-Host ("  合計: {0} 檔 / {1}" -f $pv.Count, (Format-OcfBytes $pv.TotalBytes))
    Write-Host ("  輸出: {0}" -f $pv.ZipOut)
}

# ---------------- 選單流程 ----------------

function Invoke-PackFlow {
    $w = Get-WorkingSet
    Write-Hdr '打包成 zip'
    $src = Read-Host "來源根目錄 [Enter = $($w.sourceRoot)]"
    if (-not $src) { $src = $w.sourceRoot }
    if (-not (Test-Path -LiteralPath $src)) { Write-Err2 '來源根目錄不存在'; return }
    Show-ItemsTable $w.items $src
    Write-Host "  (要改範圍請回主選單進 [5] 自訂範圍/設定檔)"
    $auth = Read-Host "收錄 auth.json？(y/N) [$($w.includeAuth)]"
    $incAuth = $w.includeAuth
    if ($auth -match '^[yY]') { $incAuth = $true } elseif ($auth -match '^[nN]') { $incAuth = $false }

    $sugZip = Get-OcfComposeZipPath -ZipDir $w.zipDir -Label $w.label
    $zipOut = Read-Host "輸出 zip [Enter = $($sugZip)]"
    if (-not $zipOut) { $zipOut = $sugZip }

    $pv = Pack-Ocf -SourceRoot $src -OutZip $zipOut -Items $w.items -Label $w.label -IncludeAuth:$incAuth -DryRun
    Write-Hdr '預覽（尚未寫入）'
    Show-PackPreview $pv
    $go = Read-Host '執行打包？(Y/n)'
    if ($go -match '^[nN]') { return }
    $res = Pack-Ocf -SourceRoot $src -OutZip $zipOut -Items $w.items -Label $w.label -IncludeAuth:$incAuth
    Write-Ok ("完成: {0}（{1} 檔，zip {2}）" -f $res.Zip, $res.Count, (Format-OcfBytes $res.ZipBytes))
    if ($res.Skipped -gt 0) { Write-Warn2 "跳過 $($res.Skipped) 檔（讀取失敗）" }
    Save-OcfLastProfile ([ordered]@{ sourceRoot=$src; label=$w.label; items=@($w.items); includeAuth=$incAuth; zipDir=(Split-Path -Parent $res.Zip); targetRoot=$w.targetRoot; updated=(Get-Date -Format 's') })
    Add-OcfHistory -Action 'pack' -Detail $w.label -Count $res.Count -Bytes $res.ZipBytes -Source $src -Target $res.Zip -Cli "Agents-Cfg-Manager.ps1 -Mode pack -SourceRoot '$src' -OutZip '$($res.Zip)'" | Out-Null
}

function Invoke-ListFlow {
    Write-Hdr '檢視 zip 內容'
    $z = Read-Host 'zip 路徑'
    if (-not $z) { return }
    $info = Read-OcfZip -Zip $z
    $m = $info.Manifest
    if ($m) {
        Write-Host ("  產生時間: {0}   來源: {1}   label: {2}   auth: {3}" -f $m.created, $m.sourceRoot, $m.label, $m.includeAuth)
    } else { Write-Warn2 '  無 manifest.json（非本工具產生的壓縮包）' }
    Write-Host ("  檔案數: {0}   解壓後大小: {1}" -f $info.Count, (Format-OcfBytes $info.Bytes))
    $n = 0
    foreach ($f in $info.Files) {
        if ($n -ge 60) { Write-Host "  ...（僅顯示前 60 筆）"; break }
        Write-Host ("    {0,10}  {1}" -f (Format-OcfBytes $f.Length), $f.Rel)
        $n++
    }
}

function Invoke-UnpackFlow {
    Write-Hdr '解壓 zip 到目標'
    $w = Get-WorkingSet
    $z = Read-Host 'zip 路徑'
    if (-not $z) { return }
    $info = Read-OcfZip -Zip $z
    if (-not $info.Manifest) { Write-Err2 '無 manifest.json，拒絕解壓'; return }
    Write-Host ("  來源: {0}  檔案數: {1}  大小: {2}" -f $info.Manifest.sourceRoot, $info.Count, (Format-OcfBytes $info.Bytes))
    $tgt = Read-Host "目標根目錄 [Enter = $($w.targetRoot)]"
    if (-not $tgt) { $tgt = $w.targetRoot }
    if (-not $tgt) { Write-Err2 '請輸入目標根目錄'; return }

    $pv = Expand-Ocf -Zip $z -TargetRoot $tgt -DryRun
    Write-Host ("  預覽: {0} 檔（新增 {1} / 覆蓋 {2}）→ {3}" -f $pv.Count, $pv.New, $pv.Overwrite, $pv.TargetRoot)
    if ($pv.OverwriteList.Count -gt 0) {
        Write-Warn2 "  將覆蓋並備份的檔案（前 20）: $($pv.OverwriteList | Select-Object -First 20)"
    }
    $go = Read-Host '執行解壓？(Y/n)'
    if ($go -match '^[nN]') { return }
    $res = Expand-Ocf -Zip $z -TargetRoot $tgt -NoBackup:$NoBackup
    Write-Ok ("完成: 寫入 {0} 檔 → {1}" -f $res.Count, $res.TargetRoot)
    if ($res.BackupRoot) { Write-Host "  舊檔備份於: $($res.BackupRoot)" }
    Save-OcfLastProfile ([ordered]@{ sourceRoot=$w.sourceRoot; label=$w.label; items=@($w.items); includeAuth=$w.includeAuth; zipDir=$w.zipDir; targetRoot=$tgt; updated=(Get-Date -Format 's') })
    Add-OcfHistory -Action 'unpack' -Detail (Split-Path -Leaf $z) -Count $res.Count -Source $z -Target $res.TargetRoot -Cli "Agents-Cfg-Manager.ps1 -Mode unpack -Zip '$z' -TargetRoot '$($res.TargetRoot)'" | Out-Null
}

function Invoke-CopyFlow {
    Write-Hdr '部署複製（目錄 → 目錄，只新增/覆蓋，不刪除）'
    $w = Get-WorkingSet
    $src = Read-Host "來源根目錄 [Enter = $($w.sourceRoot)]"
    if (-not $src) { $src = $w.sourceRoot }
    Show-ItemsTable $w.items $src
    $tgt = Read-Host '目標根目錄（例如新規畫的 repo）'
    if (-not $tgt) { return }

    $pv = Copy-Ocf -SourceRoot $src -TargetRoot $tgt -Items $w.items -DryRun
    Write-Host ("  預覽: {0} 檔（新增 {1} / 覆蓋 {2}）" -f $pv.Count, $pv.New, $pv.Overwrite)
    foreach ($s in $pv.Items) {
        $note = if ($s.Error) { "  <- $($s.Error)" } else { '' }
        Write-Host ("    {0,-32} {1,6} 檔{2}" -f $s.Path, $s.Count, $note)
    }
    if ($pv.OverwriteList.Count -gt 0) { Write-Warn2 "  將覆蓋並備份（前 20）: $($pv.OverwriteList | Select-Object -First 20)" }
    $go = Read-Host '執行複製？(Y/n)'
    if ($go -match '^[nN]') { return }
    $res = Copy-Ocf -SourceRoot $src -TargetRoot $tgt -Items $w.items -NoBackup:$NoBackup
    Write-Ok ("完成: 寫入 {0} 檔 → {1}" -f $res.Count, $res.TargetRoot)
    if ($res.BackupRoot) { Write-Host "  舊檔備份於: $($res.BackupRoot)" }
    Add-OcfHistory -Action 'copy' -Count $res.Count -Source $src -Target $res.TargetRoot -Cli "Agents-Cfg-Manager.ps1 -Mode copy -SourceRoot '$src' -TargetRoot '$($res.TargetRoot)'" | Out-Null
}

function Invoke-ScopeEditor {
    $w = Get-WorkingSet
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($it in $w.items) { $items.Add((Convert-OcfItem -Item $it)) }
    $incAuth = $w.includeAuth

    while ($true) {
        Write-Hdr '自訂範圍（结果會存為上次條件，也可另存設定檔）'
        Show-ItemsTable $items.ToArray() $w.sourceRoot
        Write-Host "  a.新增項目   r.刪除項目   t.啟用/停用   e.改排除樣式"
        Write-Host "  g.載入內建範圍(1=專案 2=全域 3=全部)   u.auth: $(if ($incAuth) {'開'} else {'關'})"
        Write-Host "  s.儲存為設定檔   l.載入設定檔   b.返回列表（自動記住）"
        $c = Read-Host '操作'
        switch ($c) {
            'a' {
                $p = Read-Host '項目相對路徑（可用 * ?，例：skills、README.md、Ai-Data\kb\*.md）'
                if ($p) {
                    $ex = Read-Host '排除樣式（逗號分隔，可留空）'
                    $exArr = @(); if ($ex) { $exArr = @($ex -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
                    $items.Add([pscustomobject]@{ path=$p; enabled=$true; exclude=$exArr })
                }
            }
            'r' { $idx = [int](Read-Host '項目編號'); if ($idx -ge 0 -and $idx -lt $items.Count) { $items.RemoveAt($idx) } }
            't' {
                $idx = [int](Read-Host '項目編號')
                if ($idx -ge 0 -and $idx -lt $items.Count) {
                    $cur = $items[$idx]
                    $items[$idx] = [pscustomobject]@{ path=$cur.path; enabled=(-not $cur.enabled); exclude=$cur.exclude }
                }
            }
            'e' {
                $idx = [int](Read-Host '項目編號')
                if ($idx -ge 0 -and $idx -lt $items.Count) {
                    $cur = $items[$idx]
                    $ex = Read-Host "排除樣式（逗號分隔，目前: $($cur.exclude -join '; ')）"
                    $exArr = @(); if ($ex) { $exArr = @($ex -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
                    $items[$idx] = [pscustomobject]@{ path=$cur.path; enabled=$cur.enabled; exclude=$exArr }
                }
            }
            'g' {
                $p = Read-Host '內建範圍 [1/2/3]'
                $preset = switch ($p) { '1' {'project'} '2' {'global'} '3' {'all'} default {'project'} }
                $items.Clear()
                foreach ($it in (Get-OcfItemsByPreset -Preset $preset)) { $items.Add($it) }
            }
            'u' { $incAuth = -not $incAuth }
            's' {
                $n = Read-Host '設定檔名稱'
                if (Test-OcfProfileName $n) {
                    Save-OcfProfile -Name $n -Data ([ordered]@{ sourceRoot=$w.sourceRoot; label=$w.label; items=@($items.ToArray()); includeAuth=$incAuth; zipDir=$w.zipDir; targetRoot=$w.targetRoot; updated=(Get-Date -Format 's') })
                    Write-Ok "已儲存設定檔: $n"
                } else { Write-Err2 '名稱不合法（不可含 \ / : * ? " < > |）' }
            }
            'l' {
                $profiles = @(Get-OcfProfiles)
                if ($profiles.Count -eq 0) { Write-Warn2 '尚無設定檔'; break }
                $i = 0; foreach ($pf in $profiles) { Write-Host ("  {0}. {1} ({2})" -f $i, $pf.Name, $pf.Updated); $i++ }
                $pick = [int](Read-Host '編號')
                if ($pick -ge 0 -and $pick -lt $profiles.Count) {
                    $d = $profiles[$pick].Data
                    $items.Clear()
                    foreach ($it in @($d.items)) { $items.Add((Convert-OcfItem -Item $it)) }
                    if ($d.sourceRoot) { $w = [pscustomobject]@{ sourceRoot=$d.sourceRoot; label=$d.label; items=$items; includeAuth=[bool]$d.includeAuth; zipDir=$d.zipDir; targetRoot=$d.targetRoot } }
                    if ($null -ne $d.includeAuth) { $incAuth = [bool]$d.includeAuth }
                    Write-Ok "已載入: $($profiles[$pick].Name)"
                }
            }
            'b' {
                Save-OcfLastProfile ([ordered]@{ sourceRoot=$w.sourceRoot; label=$w.label; items=@($items.ToArray()); includeAuth=$incAuth; zipDir=$w.zipDir; targetRoot=$w.targetRoot; updated=(Get-Date -Format 's') })
                return
            }
        }
    }
}

function Invoke-ProfileFlow {
    Write-Hdr '設定檔管理'
    $profiles = @(Get-OcfProfiles)
    if ($profiles.Count -eq 0) { Write-Warn2 '尚無設定檔（在 [5] 自訂範圍裡按 s 儲存）'; return }
    $i = 0; foreach ($pf in $profiles) { Write-Host ("  {0}. {1}  ({2}, 來源: {3})" -f $i, $pf.Name, $pf.Updated, $pf.Data.sourceRoot); $i++ }
    $pick = Read-Host '編號（Enter 取消）'
    if ($pick -eq '') { return }
    $idx = [int]$pick
    if ($idx -lt 0 -or $idx -ge $profiles.Count) { return }
    $op = Read-Host '動作: l=設為目前條件 d=刪除'
    if ($op -eq 'l') {
        $d = $profiles[$idx].Data
        Save-OcfLastProfile ([ordered]@{ sourceRoot=$d.sourceRoot; label=$d.label; items=@($d.items); includeAuth=[bool]$d.includeAuth; zipDir=$d.zipDir; targetRoot=$d.targetRoot; updated=(Get-Date -Format 's') })
        Write-Ok "已設為目前條件: $($profiles[$idx].Name)"
    } elseif ($op -eq 'd') {
        Remove-OcfProfile -Name $profiles[$idx].Name
        Write-Ok "已刪除: $($profiles[$idx].Name)"
    }
}

function Invoke-HistoryFlow {
    Write-Hdr '工作歷史（最近 100 筆）'
    $h = @(Get-OcfHistory -Limit 30)
    if ($h.Count -eq 0) { Write-Warn2 '尚無紀錄'; return }
    $i = 0
    foreach ($e in $h) {
        Write-Host ("  {0,3}. [{1}] {2,-6} {3,-10} {4,5}檔 {5,10} {6}  {7} -> {8}" -f $i, $e.time, $e.action, $e.status, $e.count, (Format-OcfBytes $e.bytes), $e.detail, $e.source, $e.target)
        $i++
    }
    $op = Read-Host '編號刪除 / c 清空 / Enter 返回'
    if ($op -eq 'c') { Clear-OcfHistory; Write-Ok '已清空'; return }
    if ($op -ne '') { Remove-OcfHistory -Id $h[[int]$op].id | Out-Null; Write-Ok '已刪除' }
}

function Show-Menu {
    Write-Host ''
    Write-Host '===== OpenCode 設定檔複製工具 =====' -ForegroundColor Green
    Write-Host '  1. 打包（目錄 → zip）'
    Write-Host '  2. 檢視 zip 內容'
    Write-Host '  3. 解壓（zip → 目錄）'
    Write-Host '  4. 部署複製（目錄 → 目錄）'
    Write-Host '  5. 自訂範圍 / 設定檔編輯'
    Write-Host '  6. 設定檔管理'
    Write-Host '  7. 工作歷史'
    Write-Host '  8. 檢查更新'
    Write-Host '  0. 離開'
}

# ---------------- Auto 模式 ----------------

function Invoke-Auto {
    try {
        switch ($Mode) {
            'pack' {
                $items = $null
                if ($Item) { $items = @($Item) }
                elseif ($Profile) {
                    $pd = Get-OcfProfile -Name $Profile
                    if (-not $pd) { throw "找不到設定檔: $Profile" }
                    $items = @($pd.items)
                    if (-not $SourceRoot -and $pd.sourceRoot) { $SourceRoot = $pd.sourceRoot }
                    if (-not $Label -and $pd.label) { $Label = $pd.label }
                    if (-not $ZipDir -and $pd.zipDir) { $ZipDir = $pd.zipDir }
                    if (-not $PSBoundParameters.ContainsKey('IncludeAuth') -and $pd.includeAuth) { $IncludeAuth = $true }
                }
                else { $items = @(Get-OcfDefaultItems) }
                if (-not $Label) { $Label = 'project' }
                if (-not $SourceRoot) { throw '需要 -SourceRoot（或可用的 -Profile）' }
                $pv = Pack-Ocf -SourceRoot $SourceRoot -OutZip $OutZip -ZipDir $ZipDir -Items $items -Label $Label -IncludeAuth:$IncludeAuth -DryRun
                if ($DryRun) {
                    Show-PackPreview $pv
                } else {
                    if (-not $Yes) {
                        Show-PackPreview $pv
                        $go = Read-Host '執行打包？(Y/n)'
                        if ($go -match '^[nN]') { exit 0 }
                    }
                    $res = Pack-Ocf -SourceRoot $SourceRoot -OutZip $OutZip -ZipDir $ZipDir -Items $items -Label $Label -IncludeAuth:$IncludeAuth
                    Write-Ok ("完成: {0}（{1} 檔，zip {2}）" -f $res.Zip, $res.Count, (Format-OcfBytes $res.ZipBytes))
                    if ($res.Failures.Count -gt 0) { $res.Failures | ForEach-Object { Write-Warn2 "跳過: $_" } }
                    Add-OcfHistory -Action 'pack' -Detail $Label -Profile $Profile -Count $res.Count -Bytes $res.ZipBytes -Source $SourceRoot -Target $res.Zip -Cli "Agents-Cfg-Manager.ps1 -Mode pack -SourceRoot '$SourceRoot' -OutZip '$($res.Zip)'" | Out-Null
                }
            }
            'list' {
                if (-not $Zip) { throw '需要 -Zip' }
                $info = Read-OcfZip -Zip $Zip
                $m = $info.Manifest
                if ($m) { Write-Host "產生時間: $($m.created)  來源: $($m.sourceRoot)  label: $($m.label)  auth: $($m.includeAuth)" }
                Write-Host "檔案數: $($info.Count)  解壓後大小: $(Format-OcfBytes $info.Bytes)"
                foreach ($f in $info.Files) { Write-Host ("  {0,10}  {1}" -f (Format-OcfBytes $f.Length), $f.Rel) }
            }
            'unpack' {
                if (-not $Zip) { throw '需要 -Zip' }
                if (-not $TargetRoot) { throw '需要 -TargetRoot' }
                $pv = Expand-Ocf -Zip $Zip -TargetRoot $TargetRoot -DryRun
                Write-Host "預覽: $($pv.Count) 檔（新增 $($pv.New) / 覆蓋 $($pv.Overwrite)）→ $($pv.TargetRoot)"
                if ($DryRun) { $pv.OverwriteList | ForEach-Object { Write-Host "  覆蓋: $_" }; return }
                if (-not $Yes) { $go = Read-Host '執行解壓？(Y/n)'; if ($go -match '^[nN]') { exit 0 } }
                $res = Expand-Ocf -Zip $Zip -TargetRoot $TargetRoot -NoBackup:$NoBackup
                Write-Ok "完成: 寫入 $($res.Count) 檔 → $($res.TargetRoot)"
                if ($res.BackupRoot) { Write-Host "舊檔備份於: $($res.BackupRoot)" }
                Add-OcfHistory -Action 'unpack' -Detail (Split-Path -Leaf $Zip) -Count $res.Count -Source $Zip -Target $res.TargetRoot -Cli "Agents-Cfg-Manager.ps1 -Mode unpack -Zip '$Zip' -TargetRoot '$TargetRoot'" | Out-Null
            }
            'copy' {
                $items = $null
                if ($Item) { $items = @($Item) }
                elseif ($Profile) {
                    $pd = Get-OcfProfile -Name $Profile
                    if (-not $pd) { throw "找不到設定檔: $Profile" }
                    $items = @($pd.items)
                    if (-not $SourceRoot -and $pd.sourceRoot) { $SourceRoot = $pd.sourceRoot }
                } else { $items = @(Get-OcfDefaultItems) }
                if (-not $SourceRoot) { throw '需要 -SourceRoot（或可用的 -Profile）' }
                if (-not $TargetRoot) { throw '需要 -TargetRoot' }
                $pv = Copy-Ocf -SourceRoot $SourceRoot -TargetRoot $TargetRoot -Items $items -DryRun
                Write-Host "預覽: $($pv.Count) 檔（新增 $($pv.New) / 覆蓋 $($pv.Overwrite)）→ $($pv.TargetRoot)"
                if ($DryRun) { $pv.OverwriteList | ForEach-Object { Write-Host "  覆蓋: $_" }; return }
                if (-not $Yes) { $go = Read-Host '執行複製？(Y/n)'; if ($go -match '^[nN]') { exit 0 } }
                $res = Copy-Ocf -SourceRoot $SourceRoot -TargetRoot $TargetRoot -Items $items -NoBackup:$NoBackup
                Write-Ok "完成: 寫入 $($res.Count) 檔 → $($res.TargetRoot)"
                if ($res.BackupRoot) { Write-Host "舊檔備份於: $($res.BackupRoot)" }
                Add-OcfHistory -Action 'copy' -Profile $Profile -Count $res.Count -Source $SourceRoot -Target $res.TargetRoot -Cli "Agents-Cfg-Manager.ps1 -Mode copy -SourceRoot '$SourceRoot' -TargetRoot '$TargetRoot'" | Out-Null
            }
            'profile' {
                switch ($Action) {
                    'list' { @(Get-OcfProfiles) | ForEach-Object { Write-Host ("{0}  ({1}, 來源: {2})" -f $_.Name, $_.Updated, $_.Data.sourceRoot) } }
                    'show' {
                        if (-not $Name) { throw '-Mode profile -Action show 需要 -Name' }
                        $d = Get-OcfProfile -Name $Name
                        if (-not $d) { throw "找不到設定檔: $Name" }
                        ConvertTo-OcfJson $d | Write-Host
                    }
                    'delete' {
                        if (-not $Name) { throw '-Mode profile -Action delete 需要 -Name' }
                        Remove-OcfProfile -Name $Name; Write-Ok "已刪除: $Name"
                    }
                    'save' {
                        if (-not $Name) { throw '-Mode profile -Action save 需要 -Name' }
                        $items = if ($Item) { @($Item) } else { @(Get-OcfDefaultItems) }
                        $src = if ($SourceRoot) { $SourceRoot } else { Get-OcfSuggestedSourceRoot }
                        Save-OcfProfile -Name $Name -Data ([ordered]@{ sourceRoot=$src; label='project'; items=$items; includeAuth=[bool]$IncludeAuth; zipDir=$ZipDir; targetRoot=$TargetRoot; updated=(Get-Date -Format 's') }) | Out-Null
                        Write-Ok "已儲存設定檔: $Name"
                    }
                }
            }
        }
        exit 0
    } catch {
        Write-Err2 "錯誤: $($_.Exception.Message)"
        exit 1
    }
}

# ---------------- 主流程 ----------------

if ($Mode) { Invoke-Auto }

while ($true) {
    Show-Menu
    $c = Read-Host '請選擇'
    try {
        switch ($c) {
            '1' { Invoke-PackFlow }
            '2' { Invoke-ListFlow }
            '3' { Invoke-UnpackFlow }
            '4' { Invoke-CopyFlow }
            '5' { Invoke-ScopeEditor }
            '6' { Invoke-ProfileFlow }
            '7' { Invoke-HistoryFlow }
            '8' { & (Join-Path $PSScriptRoot 'Standalone-Update.ps1') -Action Open }
            '0' { return }
        }
    } catch {
        Write-Err2 "錯誤: $($_.Exception.Message)"
    }
}
