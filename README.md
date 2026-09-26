# Minidoracat Vehicle Spawn Control for B42

讓伺服器管理員動態列出原版與 MOD 車輛，透過管理面板或設定檔批量調整各停車區的車輛生成數量與車型比例

Project Zomboid Build 42 MOD。

## 開發狀態

目前只建立專案與 MOD 基本骨架，尚未加入遊戲內功能。

## 規劃功能

- 開服時從原版車輛分布表自動收錄原版與 MOD 車輛
- 依停車區調整生成數量（有車機率），依 MOD／車型調整車型比例
- 管理員面板批量調整（使用 Minidoracat UI Library 介面元件）
- 伺服器端設定檔，可直接編輯，重啟後生效

## 依賴

- 必要：[Minidoracat UI Library](https://steamcommunity.com/sharedfiles/filedetails/?id=3789836701)（`MinidoracatUIFor42`）

## 安裝

- Steam Workshop：（首次上傳後補上連結）
- 手動安裝：把 `MOD/MinidoracatVehicleSpawnControlFor42/Contents/mods/MinidoracatVehicleSpawnControlFor42` 複製到 `%USERPROFILE%\Zomboid\mods\` 並將資料夾改名為 `MinidoracatVehicleSpawnControlFor42`

## 開發

- `link_workshop.bat`：手動同步、唯讀狀態與歸檔卸載；MOD 以實體副本放入 `Zomboid\Workshop\` 與 `Zomboid\mods\`，不使用目錄連結
- `PZ_Test.bat`：暗色點選視窗，啟動前增量同步目前 MOD 與家族依賴；首次預設 no-Steam，之後記住各專案的選擇。需要換檔但遊戲仍在執行時拒絕同步與新啟動，不停止既有遊戲；完整驗證與資料邊界見 `../pz-family-docs/tools.md`
- `Publish_Workshop.bat`：發布到 Steam Workshop（需 Steam 用戶端已登入；可選擇只更新內容／封面／簡介；首發仍走遊戲內上傳器）

## 版本

版本號格式：`{PZ 版本}-{mod 版本}`（例 `42.20.4-0.1.0`），詳見 [CHANGELOG.md](CHANGELOG.md)。

## 作者

Minidoracat — [Discord](https://discord.gg/Gur2V67) | [Twitch](https://www.twitch.tv/minidoracat)
