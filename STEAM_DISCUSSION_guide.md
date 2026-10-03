<!-- Steam 討論區貼文稿源（繁中）；簡介只放摘要，詳細內容以本串為準 -->
<!-- 討論串網址：https://steamcommunity.com/workshop/filedetails/discussion/3812410742/586187704184634450/ -->
<!-- 標題：📖 Vehicle Spawn Control 完整說明：面板操作與設定檔 -->

[b]English version:[/b] [url=https://steamcommunity.com/workshop/filedetails/discussion/3812410742/586187704184634439/]Vehicle Spawn Control Guide: Panel & Config File[/url]

車輛生成控制讓伺服器管理員（或單人玩家）決定：世界生成新車時，各區域生成多少車、生成哪些車。可以在遊戲內面板操作，也可以直接編輯設定檔。本串整理每項功能、設定檔格式、已知限制與常見問題。

[h2]🚀 快速上手[/h2]
[list]
[*] 一併訂閱必要前置 [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3789836701]Minidoracat UI Library for B42[/url]；多人遊戲需要伺服器啟用本 MOD。
[/list]
[olist]
[*] 多人：具備「沙盒設定」權限的管理員打開原版管理面板，按最後一格「車輛生成控制」。
[*] 單人：在地上按右鍵，選「車輛生成控制」。
[*] 在「車輛」或「區域」分頁調整後按「套用變更」。之後才生成的區塊會照新設定，已經生成的車不會變。
[*] 不想進遊戲也行：直接編輯設定檔 config.json，存檔後約一分鐘內自動生效（位置見下方「設定檔」）。
[/olist]

[h2]✨ 功能詳解[/h2]
[h3]自動收錄車輛[/h3]
[list]
[*] 開服時讀取所有車輛與各區域的車輛分布，原版與 MOD 新增的車都會列出，不必手動登記。
[*] 來源 MOD 依遊戲實際載入車輛的紀錄判斷，不看車名前綴；被 MOD 覆寫的原版車仍算原版，並列出覆寫它的 MOD。
[*] 同名的變體（同一款車的燒毀版、撞爛版等）自動收成一組，可以整組調整。
[*] 首次安裝本 MOD 之後才出現的車會標示「新偵測」，可以設定讓它們先不生成（見設定檔的 newVehicles）。
[/list]

[h3]調整生成數量[/h3]
[list]
[*] 「區域」分頁可以調每格生成機率：它決定這個區域的停車格有多少會生車。
[*] 另外可以調一般車、燒毀車、特殊車、零件損壞、附鑰匙的機率與車況。
[*] 沙盒的「車輛產生率」仍然有效，會再乘上每格生成機率；面板會顯示目前的沙盒值。
[/list]

[h3]調整車型比例[/h3]
[list]
[*] [b]整包倍率[/b]：在「車輛」分頁選一個來源（原版或某個 MOD），一次讓它所有的車在所有區域變多或變少；設為 0 等於整包停用。
[*] [b]單車倍率與停用[/b]：選一台車，可以設定「所有區域倍率」，或在所有區域停用它。
[*] [b]區域權重[/b]：在「區域」分頁調某區每台車的權重，也可以把車加進原本沒有它的區域；權重 0 會從這區移除。
[*] [b]生成塗裝[/b]：可以指定某區生成某台車時用第幾款塗裝，或維持隨機。
[*] 實際權重＝區域權重 × 車款倍率 × 來源倍率。權重是同一區內的相對比例：調低某個來源，其他車的占比會上升，但這區生成的車總數不變（總數由每格生成機率決定）。
[*] 占比和原本不同時，會同時顯示原本的占比（例如「原 17.8%　9.4%」），方便看出調整幅度。
[/list]

[h3]3D 預覽與塗裝色票[/h3]
[list]
[*] 左鍵拖曳旋轉、右鍵拖曳平移、滾輪縮放、雙擊重設；也有正面、側面、俯視按鈕。
[*] 預覽固定顯示第一款塗裝與預設車色，這是遊戲引擎的限制：遊戲的 3D 預覽元件只會載入每台車的第一款塗裝，也沒有提供切換塗裝的功能。實際生成的車不受影響，各款塗裝照常出現。多塗裝的車會在預覽下方列出每款塗裝的貼圖色票，滑鼠移上去可放大查看。
[/list]

[h3]批次調整[/h3]
[list]
[*] 車輛清單可以多選：Ctrl 加選、Shift 選一段、勾選框全選。選了兩台以上，右欄會變成批次操作：設定倍率、加入或移出區域、在所有區域停用或啟用。
[*] 區域分頁的車款表同樣支援點選、Ctrl／Shift 多選與全選，可以一起減半、加倍、設定權重、移出此區域或還原。點組成長條上的來源，可以直接選取它在這區的所有車。
[/list]

[h3]設定檔同步[/h3]
[list]
[*] 每分鐘檢查一次 config.json，內容有變才重新讀取；成功就套用並更新 status.json。
[*] 寫錯時整份拒絕、保留原本生效的設定，並在 status.json 與面板的「設定檔同步」分頁寫出第幾行或哪個欄位、該怎麼改。
[*] 有人在你編輯面板時改了設定檔，按套用前會先詢問要不要覆寫。
[/list]

[h3]變更紀錄與還原[/h3]
[list]
[*] 每次套用都記下修訂號、時間、來源（面板、設定檔、開服或還原）、誰改的，以及改了哪些項目。
[*] 可以還原到最近 10 次生效過的任一版本。
[*] 伺服器關閉期間有人直接改過設定檔，下次開服也會列出差異。
[/list]

[h3]權限[/h3]
[list]
[*] 多人：沿用原版角色的「沙盒設定」權限（預設版主與管理員有，GM 沒有）。管理員可以在角色設定把這個權限給任何角色；伺服器端每個寫入命令都會再檢查一次。
[*] 單人：不檢查權限。
[/list]

[h2]⚙️ 設定檔[/h2]
設定檔在 Zomboid 資料夾的 [b]Lua/MinidoracatVehicleSpawnControl/[/b]：
[list]
[*] [b]專用伺服器[/b]：伺服器主機的 Zomboid/Lua/MinidoracatVehicleSpawnControl/（啟動參數有指定 -cachedir 時，改用該目錄）
[*] [b]開房合作（Co-op）與單人[/b]：開房玩家本機的 %USERPROFILE%/Zomboid/Lua/MinidoracatVehicleSpawnControl/
[/list]
[list]
[*] [b]config.json[/b]：你編輯的設定，只記和原本不同的地方。
[*] [b]catalog.json[/b]（唯讀）：所有車款、來源 MOD、出現在哪些區域與實際占比。要填車款名或區域名時照這份抄。
[*] [b]status.json[/b]（唯讀）：最近一次檢查是否成功、錯誤、警告與新偵測的車。
[*] [b]history.json、backups/[/b]：變更紀錄與最近 10 份生效設定的備份。
[*] [b]state.json[/b]：內部狀態，不要手動修改。
[/list]

[code]
{
  "schema": 1,
  "newVehicles": "keep",
  "sources": {
    "pz-vanilla": { "multiplier": 1.0 },
    "SomeVehiclePack": { "multiplier": 0.5 }
  },
  "vehicles": {
    "Base.CarLightsPolice": { "enabled": false },
    "Base.PickUpTruck": { "multiplier": 2.0 }
  },
  "zones": {
    "parkingstall": {
      "spawnRate": 16,
      "chanceToSpawnBurnt": 0,
      "weights": { "Base.CarNormal": 20, "Base.VanAmbulance": 3 },
      "skins": { "Base.CarNormal": 2 }
    }
  }
}
[/code]
[list]
[*] [b]newVehicles[/b]："keep" 照各 MOD 自己的比例；"disable" 讓新偵測的車先不生成，要在 vehicles 裡寫 "enabled": true 才開。
[*] [b]sources[/b]：來源 MOD 的 ID 對應倍率；原版是 pz-vanilla。
[*] [b]vehicles[/b]：完整車款名（Module.Script）對應 "enabled"（true／false）與 "multiplier"（≥ 0）。
[*] [b]zones[/b]：區域名對應區域參數、weights 與 skins。區域參數有 spawnRate、chanceToSpawnNormal、chanceToSpawnBurnt、chanceToSpawnSpecial、chanceToPartDamage、chanceToSpawnKey（0–100）與 baseVehicleQuality（0–2）。
[*] [b]weights[/b]：權重 ≥ 0；0 會從這區移除，也可以加入原本沒有的車。[b]skins[/b]：塗裝序號，-1 是隨機。
[*] 區域名要和 catalog.json 完全相同，大小寫也算；business2 到 business12 是 business 的別名，請寫 business。
[*] 寫到已移除的車或區域只會列成警告，不會擋下整份設定。每次套用都從開服時的原始分布重算，舊設定不會殘留。
[/list]

[h2]⚠️ 已知限制[/h2]
[list]
[*] 只影響之後第一次生成的區塊；已經生成過的區塊不會重抽。
[*] 部分隨機事件會直接指定車型（例如某些車禍現場），不經區域分布，本 MOD 管不到。
[*] 3D 預覽受遊戲引擎限制，只能顯示第一款塗裝與預設車色（實際生成不受影響），其他塗裝以貼圖色票呈現。
[*] 設定檔放在使用者資料夾：同一個資料夾下的所有單人存檔與自架伺服器共用同一份設定。
[/list]

[h2]❓ 常見問題[/h2]
[list]
[*] [b]改了設定，路上的車沒變？[/b] 設定只影響之後新生成的區塊，到還沒去過的地方看。
[*] [b]權重調高了，車的總數卻沒變多？[/b] 權重是區內的相對比例；要讓車變多，調每格生成機率或沙盒的車輛產生率。
[*] [b]3D 預覽為什麼換不了塗裝，車色也固定？[/b] 這是遊戲引擎的限制：遊戲的 3D 預覽元件只會載入每台車的第一款塗裝與預設車色，沒有切換的功能。實際生成的車不受影響；其他塗裝請把滑鼠移到預覽下方的色票放大查看。
[*] [b]想讓某個 MOD 的車少一點？[/b] 「車輛」分頁選那個 MOD，調低整包倍率。
[*] [b]設定檔改了沒生效？[/b] 看 status.json 或面板「設定檔同步」分頁列出的錯誤；寫錯時會保留原本的設定。
[*] [b]剛裝了新的車輛 MOD，不想它馬上出現？[/b] 把 newVehicles 設成 "disable"，確認後再逐台開啟。
[*] [b]和其他會改車輛分布的 MOD 一起用？[/b] 開服前改好分布的 MOD 會被正常收錄；開服之後才改分布的，改動會在本 MOD 下次套用時被覆蓋。
[*] [b]移除本 MOD 會怎樣？[/b] 車輛分布回到原版與各 MOD 的設定；已經生成的車留在世界上；設定檔留在資料夾裡，不影響存檔。
[/list]

[h2]💬 回報[/h2]
回報問題時請附上 status.json，以及伺服器 log（server-console.txt；單人是 console.txt）裡以 [MinidoracatVehicleSpawnControlFor42] 開頭的幾行。
[list]
[*] [url=https://github.com/Minidoracat/MinidoracatVehicleSpawnControlFor42/issues]GitHub Issues[/url]
[*] [url=https://discord.gg/Gur2V67]Discord[/url]
[/list]
