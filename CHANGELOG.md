# Changelog — Agents Cfg Manager

## v1.2.0 (2026-11-13)

### 改名：Opencode Cfg Manager → Agents Cfg Manager

- 顯示名稱改為 Agents Cfg Manager（`tool.json`、頁首、`<title>`、`/api/info`、README）。
- 工具 id 改為 `agents-cfg-manager`（原 `opencode-cfg-manager`）。
- 入口檔改名：`Cfg-Manager.ps1` → `Agents-Cfg-Manager.ps1`、`Cfg-Manager-Web.ps1` → `Agents-Cfg-Manager-Web.ps1`、
  `Run-Cfg-Manager.bat` → `Run-Agents-Cfg-Manager.bat`、`Run-Cfg-Manager-Web.bat` → `Run-Agents-Cfg-Manager-Web.bat`。
  自訂的排程或捷徑若直接呼叫舊檔名，請改用新檔名。
- 資料夾改為 `%LOCALAPPDATA%\DevToolbox\agents-cfg-manager`（`%DEVTOOLBOX_DATA%` 下同理）。
  第一次啟動時若新資料夾不存在、舊的 `opencode-cfg-manager` 存在，會整份複製過來；舊資料夾保留不刪，確認無誤後可自行刪除。
- 打包檔名預設樣式改為 `agents-cfg_<ts>_<label>.zip`（已存的設定檔裡自訂的樣式不受影響）。
- 在 Dev-Toolbox 中的子模組資料夾改為 `tools/Agents-Cfg-Manager`；GitHub repo 名稱（`cfg-manager`）不變。

### 變更

- 頂部改用與 Git Ref Manager 一致的兩列配置，實際 port 放在連線狀態左側，分頁獨立成一列。

## v1.1.2 (2026-11-11)

- 寬螢幕配置：移除 `main` 的 1180px 上限，內容隨視窗撐滿，左右 padding 改 clamp 響應式

## v1.1.1 (2026-11-10)

- Dev-Toolbox 嵌入支援：`?embedded=1` 時隱藏品牌與 port 資訊（Hub 已顯示），保留分頁導覽
- 導入 Dev-Toolbox 設計系統：`ui/ui-kit.css`（`Sync-UiKit.ps1` 同步），連結於 `style.css` 之前；
  `:root` 補 `color-scheme: dark`（本工具只有深色）

## v1.1.0 (2026-11-10)

- TOOL-SPEC v1 合規：`tool.json`、啟動印 `READY` 行、`-ParentPid` 跟隨 Hub 結束、
  `-DataDir` 與 `%LOCALAPPDATA%\DevToolbox\opencode-cfg-manager`（舊 profiles／history 首次自動搬移）、
  `GET /api/health`、`GET /api/info`、安全標頭與 Host／Origin／`X-Toolbox-Request` 檢查
- 錯誤回應統一為 `{ ok:false, error:{ code, message, detail } }`；前端同步
- `-OpenBrowser` 改為明顯開啟瀏覽器（舊 `-NoBrowser` 移除）；雙擊 Run-Web.bat 預設開瀏覽器
- packs 預設輸出改到資料目錄下的 `packs\`

## v1.0.0

- 初版：CLI 與 Web 的打包／部署／設定檔管理
