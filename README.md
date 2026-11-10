# Agents Cfg Manager

AI agent 設定檔打包／部署工具：把 `opencode.json`、`AGENTS.md`、`Ai-Data\`、`.opencode\`（skills/agents/commands）等
打包成 zip、從 zip 還原，或直接把一套設定部署到另一個專案（新規畫 repo）。
CLI 與 Web 共用同一套核心邏輯（`CfgCore.ps1`）。

## 啟動

| 方式 | 檔案 | 說明 |
|---|---|---|
| CLI 選單 | `Run-Agents-Cfg-Manager.bat` | 雙擊啟動，選單操作 |
| Web 控制台 | `Run-Agents-Cfg-Manager-Web.bat` | 雙擊啟動本機服務（預設 http://127.0.0.1:8712）並自動開瀏覽器；Ctrl+C 停止 |

無外部相依，Windows 內建 PowerShell 5.1 即可（7.x 亦可）。僅綁定 127.0.0.1。

## 範圍模型（項目式）

每一筆項目＝相對來源根的檔案或資料夾（資料夾遞迴，支援 `*` `?` 萬用字元），可逐項啟用／停用／加排除樣式。

預設範圍（專案）：`opencode.json`、`opencode.jsonc`、`AGENTS.md`、`Ai-Data\`、`.opencode\`。
內建 preset：專案／全域（`~\.config\opencode`）／全部（全域項目以 `~\.config\opencode` 為 base，預設停用，可自行啟用）。
`node_modules`、`opencode.db*` 一律強制排除。

## 設定檔（Profile）

一套「來源根＋項目清單＋auth＋輸出／目標目錄」可存成 `profiles\<名稱>.json`，CLI 與 Web 共用。
`profiles\_last.json` 自動記住上次條件。

```powershell
# 建立：只包特定項目（支援萬用字元）
.\Agents-Cfg-Manager.ps1 -Mode profile -Action save -Name PlatformA標準包 -SourceRoot C:\src\sample -Item AGENTS.md,opencode.json,'.opencode\skills'

# 用設定檔打包
.\Agents-Cfg-Manager.ps1 -Mode pack -Profile PlatformA標準包 -Yes

# 管理
.\Agents-Cfg-Manager.ps1 -Mode profile -Action list
.\Agents-Cfg-Manager.ps1 -Mode profile -Action show   -Name PlatformA標準包
.\Agents-Cfg-Manager.ps1 -Mode profile -Action delete -Name PlatformA標準包
```

## CLI Auto 模式（供腳本呼叫，exit 0/1）

```powershell
# 打包（-DryRun 只預覽）
.\Agents-Cfg-Manager.ps1 -Mode pack   -SourceRoot C:\src\sample -OutZip E:\cfg.zip [-IncludeAuth] [-DryRun] -Yes
# 看 zip 內容
.\Agents-Cfg-Manager.ps1 -Mode list   -Zip E:\cfg.zip
# 解壓（覆蓋前自動備份到 <目標>\_backup\restore-<時間戳>\）
.\Agents-Cfg-Manager.ps1 -Mode unpack -Zip E:\cfg.zip -TargetRoot D:\新專案 [-NoBackup] [-DryRun] -Yes
# 部署複製（目錄→目錄，只新增/覆蓋，不刪除）
.\Agents-Cfg-Manager.ps1 -Mode copy   -SourceRoot C:\src\sample -TargetRoot D:\新專案 [-Item AGENTS.md,.opencode] [-DryRun] -Yes
```

## 安全規則

- 只 merge 不刪除；覆蓋前舊檔搬到目標旁 `_backup\<動作>-<時間戳>\`（`-NoBackup`／Web 勾選可關）
- 所有動作先顯示預覽（新增／覆蓋清單），CLI 選單與 Web 都有 Dry-Run
- 來源在目標內部（或反之）→ 直接拒絕，防止遞迴複製
- zip 內嵌 `manifest.json`（產生時間、來源、檔案清單），非本工具的 zip 拒絕解壓；zip 內路徑含 `..` 一律跳過
- `auth.json`（`~\.local\share\opencode\`）預設不收，需明確勾選／`-IncludeAuth`，收錄時放在 zip 的 `.share\` 下

## 其他

- 工作歷史：`job-history.jsonl`（最近 100 筆；Web「歷史」頁可複製 CLI 指令／刪除／清空）
- 預設輸出資料夾：`packs\`
- Ai-Data 全收約 500+ MB（含文件與索引）；只想包部分請用自訂項目（例 `Ai-Data\kb\*`）或加排除樣式
- Web 停止：控制台 Ctrl+C，或 `Invoke-RestMethod -Method Post http://127.0.0.1:8712/api/shutdown`
