# 車輛生成控制：設計提案

狀態：介面方向定案為 **C 車輛展示間**（2026-09-26）；其餘待決定見第 8 節。定稿視覺稿 `images/C1-*.png`、`images/C2-*.png`，prompt 在 `images/PROMPTS.md`。
證據行號：Java 以反編譯快照根目錄（`environment.md` 指定版本）為基準，原版 Lua 以 `ProjectZomboid/media/` 為基準。

## 1. 範圍

本 MOD 控制「世界生成新車時，各區域生成多少車、生成哪些車型」。不處理已存在於世界上的車（所有權、刪除、傳送屬 `MinidoracatVehicleManagerFor42`）。

## 2. 需求可行性

| 需求 | 判定 | 依據 | 做法 |
|---|---|---|---|
| 遊戲內面板批量管理 | 可行 | 分布表是 Lua 全域 `VehicleZoneDistribution`（`lua/shared/VehicleZoneDefinition.lua:1-26`） | 伺服器端改表，面板只送意圖 |
| 自動加入 MOD 車輛 | 可行 | `ScriptManager.getAllVehicleScripts()`（`ScriptManager.java:848-854`） | 開服時列舉全部車輛 script |
| 原版／MOD 分類 | 可行 | `BaseScriptObject.getLoadedScriptBodies()` 交錯記錄 modId／body（`BaseScriptObject.java:137-144`、`ScriptBucket.java:98-132`），原版為 `pz-vanilla`（`ScriptManager.java:651`）；`getModInfoByID` 取 MOD 名（`LuaManager.java:5364-5368`） | 以來源 modId 分類，**不看 module 名**（MOD 常用 `module Base`） |
| JSON 改檔自動同步 | 可行（輪詢） | Lua 只能讀寫 `<cacheDir>/Lua/`，沒有 mtime API（`LuaManager.java:5933-5959,6020-6031`） | 每分鐘讀檔比對內容，變了才解析驗證 |
| 改完立即影響遊戲 | **待實機驗證** | Java 在第一次生車時把 Lua 表複製成快取（`VehicleType.java:38-126`、`IsoChunk.java:1726-1730`）；`VehicleType.Reset()` 可清快取且類別有對 Lua 公開（`VehicleType.java:231-234`、`LuaManager.java:2440`） | 改表後呼叫 `Reset()`；若實機不安全，退回「重啟生效」 |
| 3D 外觀預覽 | 可行（預設塗裝） | `UI3DScene` 的 `createVehicle`／`setVehicleScript`（`UI3DScene.java:590-598,1424-1427`），非 debug 限定 | 單一場景，只在選車時渲染 |
| 切換塗裝預覽 | **原版 API 做不到** | 場景初始化只取 `getSkin(0)` 並快取（`UI3DScene.java:6101-6111`）；`VehicleScript.skins` 為 private、無修改 API（`VehicleScript.java:102-104`） | 列出塗裝清單並可指定「生成塗裝」；3D 固定顯示第一款 |
| 切換顏色預覽 | **原版 API 做不到** | 預覽車漆色寫死（`UI3DScene.java:7040-7050`）；真車顏色是生成時隨機 HSV（`BaseVehicle.java:729-772`） | 顯示「隨機車色」或 script 的固定色 |

## 3. 設計必須遵守的限制

1. **只影響之後新生成的區塊。**車輛只在區塊第一次載入且未被車輛資料庫看過時生成（`IsoChunk.java:3708-3710`）；已生成的車不會重抽。介面要明講，不能讓管理員以為整張地圖會重配。
2. **伺服器是唯一權威。**MP client 不跑生車（`IsoChunk.java:1732` 的 `!GameClient.client`），面板只送意圖，伺服器驗證權限與 schema 後套用。
3. **權重是相對值。**Java 會把同區域權重正規化成百分比（`VehicleType.java:56-63`），所以面板要同時顯示「權重」和「實際占比」。
4. **區域不只停車場。**原版有 40 多個區域：一般停車、住宅品質、交通壅塞、品牌／服務車、故事用分布（`trades`、`delivery` 等，`VehicleZoneDefinition.lua:501-577`）；`business2`–`business12` 是 `business` 的別名（`:454-464`），不能當成獨立區域寫回。MOD 也會新增區域，清單以執行期的表為準。
5. **不是所有車都走區域表。**部分故事事件直接指定車型（例 `RVSAmbulanceCrash.java:57-60`、`RVSRichJerk.java:98-102`），本 MOD 管不到。
6. **同名車很多。**原版繁中翻譯有 34 個 script 都叫「富蘭克林·瓦盧林」、損毀版也共用名稱（`Translate/CH/IG_UI.json` 的 `IGUI_VehicleName*`）。清單必須顯示 script 名，並能按車款分組批次處理。
7. **大型資料不整包廣播。**單一命令走 1 MB 緩衝（`UdpConnection.java:39-44`）；按目前區域或搜尋結果分頁傳給 client。
8. **區域內不能留下「全部權重為 0」。**`init()` 以 `100 / 權重總和` 正規化（`VehicleType.java:72-81`），總和為 0 時每台車的權重會變成 NaN。停用車輛要把它從該區的 `vehicles` 表移除；整區都停用就把 `spawnRate` 設成 0，不要留下空的權重。
9. **區域名一律小寫。**`init()` 用原樣的鍵存入快取（`VehicleType.java:55,135`），查詢時卻先轉小寫（`:160,173`）。大小寫混用的區域名會查不到。

## 4. 資料模型

### 4.1 設定檔：`Zomboid/Lua/MinidoracatVehicleSpawnControl/config.json`

管理員可直接編輯的唯一檔案。只記錄「和預設不同的地方」，沒寫到的就沿用原版／各 MOD 自己的設定。

```json
{
  "schema": 1,
  "revision": 42,
  "newVehicles": "keep",
  "sources": {
    "pz-vanilla": { "multiplier": 1.0 },
    "SomeMilitaryPack": { "multiplier": 0.5 }
  },
  "vehicles": {
    "Base.CarLightsPolice": { "enabled": false },
    "MilPack.M35": { "multiplier": 2.0 }
  },
  "zones": {
    "parkingstall": {
      "spawnRate": 16,
      "chanceToSpawnBurnt": 0,
      "weights": { "Base.CarNormal": 20, "MilPack.M35": 0 },
      "skins": { "Base.VanSeats_Mural": 2 }
    }
  }
}
```

實際權重 ＝ 區域權重（有覆寫用覆寫，否則用原設定）× 車輛倍率 × 來源倍率；`enabled:false` 一律為 0。優先序固定、不需排序，面板與 JSON 一看就懂。

- `newVehicles`：新偵測到的 MOD 車輛怎麼處理——`keep`（照該 MOD 自己的比例）或 `disable`（先不生成，等管理員開啟）。
- 設定檔引用到已移除的車或區域：保留在檔案裡、面板標「遺失」，不刪、不報錯中斷。

### 4.2 車輛目錄：`catalog.json`（唯讀，開服自動產生）

列出所有車輛 script、顯示名、來源 MOD、所屬區域與原始權重、塗裝數，以及所有區域的原始參數。讓管理員不進遊戲也知道能填哪些 script 名與區域名。

### 4.3 同步流程（見 `images/D-json-sync-flow.png`）

1. 每次寫入前先把舊檔備份到 `backups/`（保留最近 N 份）。
2. 伺服器每 60 秒（真實時間，用 `getTimestampMs` 節流，`LuaManager.java:9268`）讀一次 `config.json`，內容沒變就跳過。遊戲時間事件會隨日長設定變快變慢（`GameTime.java:646-656`），不拿來當計時器。
3. 變了就解析與驗證；失敗時保留舊設定，並把「第幾行、哪個欄位、怎麼修」通知線上管理員。
4. 成功就套用並把修訂號加一，線上管理員的面板自動重新整理。
5. 管理員在面板編輯期間若檔案被外部修改，按「套用變更」時要求選擇「重新載入」或「覆寫」（沿用 Economy `ECCodec.lua:157-224` 的 stale 比對模式）。

## 5. 介面候選

三個候選共用同一套後端與設定檔，差別在「管理員最常從哪裡開始」。

| | A 區域工作台 | B 規則矩陣 | C 車輛展示間 |
|---|---|---|---|
| 視覺稿 | `images/A-zone-workbench.png` | `images/B-rule-matrix.png` | `images/C-vehicle-showroom.png` |
| 主軸 | 先選區域，再調這區的車 | 車款 × 區域一覽，用規則批次改 | 先選車，再看它在哪些區域生成 |
| 最適合 | 「這個停車場車太多／太雜」 | 「所有 MOD 車減半」「軍車只在基地出現」 | 「這台 MOD 車我想讓它常見一點」 |
| 3D 預覽 | 右欄中型 | 小縮圖 | 中央大舞台 |
| 批次操作 | 勾選多台後倍率／停用 | 規則卡片 | 「套用到全部變體」 |
| 實作成本 | 中（清單＋參數＋預覽） | 高（自製矩陣格線、規則排序、全量資料） | 中（但區域參數要另開分頁） |
| 主要風險 | 跨區域的大範圍調整要點很多次 | 資料量最大、MP 傳輸最重；新手難懂 | 看不到單一區域的整體組成 |

**定案：C 車輛展示間。**分頁為「車輛」（C1，先選車再調它在各區域的權重，含「套用到全部變體」）與「區域」（C2，補上 C 看不到單一區域整體組成的缺口：區域參數、來源組成長條、車款表與批次列）。批次調整採第 4.1 節的固定三層倍率（來源／車輛／區域），不做 B 的可排序規則。

### 5.1 視覺稿審查後的介面規則（不論選哪案都適用）

1. 長清單與矩陣一律用原版 `ISScrollingListBox` 自帶捲軸，最後一列露出半列；矩陣固定首欄並顯示「顯示 7／44 個區域」這類計數。
2. 紅色只給「在所有區域停用此車」這類破壞性操作；關閉鈕與「已停用」狀態用中性色＋圖示。
3. 琥珀色只代表「可操作／已選取」。「未套用 N 項變更」做成按鈕，點開列出待套用的變更；「新偵測」「已修改」用中性色＋圖示。
4. 熱度或比例底色上的文字依底色亮度切換深／淺字，確保至少 4.5:1。
5. 分頁統一叫「區域」，不叫「停車區域」（區域包含警察局、農場、故事分布）。
6. 清單列不放車輛縮圖：遊戲沒有現成縮圖，逐列建 3D 場景又太貴；預覽只保留一個場景。

### 5.2 入口與權限

**入口：原版管理面板（`ISAdminPanelUI`）多一顆「車輛生成控制」按鈕。**

- 原版在 `create()` 裡先加入所有按鈕，再依標題排序、排成兩欄，最後把「關閉」放在底部（`ISAdminPanelUI.lua:157-189`）。**本 MOD 的按鈕固定排在所有原版按鈕之後，不改動任何原版按鈕的位置。**做法是包裝 `create`：等原函式跑完，再把按鈕放進兩欄格子的下一格，寬度與間距沿用原版按鈕（`getWidth()`、`BUTTON_HGT`、`UI_BORDER_SPACING`）；接著把 `self.cancel` 下移一列，並用 `setHeight` 撐高面板。Workshop 上有 MOD 把按鈕直接貼在右下角（Skill Recovery Journal），會和「關閉」鈕搶位置，不採用。
- 另外包裝 `updateButtons`：先呼叫原函式（可能因權限不足直接關掉面板並 return，`:194-240`），再依權限設定本按鈕的 `enable`。原版在權限變動時會重新呼叫它（`RefreshCheats`、`OnRolesReceived`，`:412-441`），所以不需要自己輪詢。
- 管理面板只在多人連線時出現：左側圖示在 `isClient()` 內才建立（`ISEquippedItem.lua:905,939-941`），顯示條件是 `Role:hasAdminTool()`（`:147`、`Role.java:193-209`）。**單人模式沒有這個入口**；單人玩家改用 JSON 檔。debug 模式則照 Skill Recovery Journal 的做法，在 `ISDebugMenu` 加一顆按鈕，方便實機測試。
- 面板本身沿用原版管理工具的慣例：`ISCollapsableWindow`、單一實例、再按一次就關閉。

**權限：沿用原版角色權限（Role／Capability），不另建名單。**

| 動作 | 需要的權限 | 原版預設誰有 |
|---|---|---|
| 看到按鈕、開啟面板、讀取設定 | `Capability.SandboxOptions` | moderator、admin（`Roles.java:448-471`）；gm 沒有（`:408-447`） |
| 套用變更、還原修訂 | 同上，**伺服器端**在 `OnClientCommand` 裡再檢查一次 | 同上 |

- 選 `SandboxOptions` 的理由：車輛生成比例屬於世界生成規則，性質和原版「沙盒設定」按鈕相同（原版以同一權限控管，`ISAdminPanelUI.lua:226`；封包層 `PacketTypes.java:411`）。家族 ItemCleaner 的沙盒寫入也用這個權限。
- 如果要**只限 admin**，改用 `Capability.ChangeAndReloadServerOptions`（moderator 預設被拿掉，`Roles.java:457`）。
- B42 的角色可以在伺服器上自訂，管理員可以把權限發給任何角色，不必改 MOD。
- UI 上的 `enable` 只是方便使用，真正的防線在伺服器：每個寫入命令都要重新檢查 `player:getRole():hasCapability(...)`。

## 6. 功能建議（原需求以外）

必要（沒有會出事或很難用）：

1. **實際占比顯示**：權重旁邊同時顯示正規化後的百分比。
2. **車款分組**：同名變體收成一組，可整組批次調整。
3. **新車政策與「新偵測」標記**：新 MOD 車第一次出現時標記，照 `newVehicles` 政策處理。
4. **車輛目錄匯出**：沒有 `catalog.json`，離線改 JSON 等於盲改。
5. **自動備份＋變更紀錄**：誰、何時、從面板或檔案、改了什麼；可一鍵還原到某個修訂。
6. **生效範圍提示**：面板與 Steam 說明都寫清楚「只影響之後新生成的區塊」。

建議（明顯加分）：

7. **區域數量參數**：每格生成機率、燒毀車、特殊車、車況、鑰匙機率；並唯讀顯示沙盒的 `CarSpawnRate`，說明它與區域參數的關係（`IsoChunk.java:963-982`）。
8. **指定生成塗裝**：區域表本來就能指定塗裝（`index`，`-1` 為隨機），可取代做不到的 3D 塗裝切換。
9. **故事分布分類**：`trades`、`delivery` 等表可以調，放在「進階」分組並註明只影響使用這些表的故事事件。
10. **權限**：沿用原版角色權限，見第 5.2 節。

暫不做（目前證據不支持或屬其他 MOD）：

- 3D 塗裝／顏色切換：需要 Java 層改動，Workshop MOD 做不到。
- 重配已生成的車：屬 VehicleManager 的範圍。
- 控制直接指定車型的故事事件：原版沒有入口。

## 7. 實作前要先驗證的事

1. **`VehicleType.Reset()` 在執行中的專用伺服器是否安全**：決定「立即生效」或「重啟生效」。區塊生車在 `doLoadGridsquare` 內（`IsoChunk.java:3691-3714`），要實測與區塊載入同時發生時會不會出錯。
2. **套用時機**：若 `Reset()` 可用，開服後任何時間套用都行；若不可用，必須在所有車輛 MOD 的生成表腳本之後、第一次生車之前套用，需實測事件順序。
3. **一般 MP client 的 3D 預覽**：`UI3DScene` 沒有 debug 限制，但只在 debug 工具裡被使用過，需實機確認。
4. **JSON 解析**：原版沒有 Lua JSON 函式庫；複製 Economy 的 `ECCore.lua` codec 到本 MOD 命名空間（第三個 consumer 出現時再抽共用）。

## 8. 待決定

1. ~~介面方向~~：已定案 C（見第 5 節）。
2. ~~`newVehicles` 預設值~~：`keep`（2026-09-26 定案）。
3. 若 `Reset()` 不安全，退回「修改後重啟生效」（2026-09-26 同意；待第 7 節驗證）。
4. ~~3D 預覽~~：放 v1（2026-09-26 定案；待第 7 節驗證 MP 客戶端可用）。
5. ~~面板權限~~：`Capability.SandboxOptions`（2026-09-26 定案）。
