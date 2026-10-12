<!-- 指南網址：https://steamcommunity.com/sharedfiles/filedetails/?id=3817839865 -->
<!-- Steam 指南稿源（繁中）：MOD 的完整說明以本指南為準，簡介只放摘要。格式與同步方式見 pz-family-docs/release.md「完整說明：Steam 指南」 -->
<!-- 標題：📖 車輛生成控制 Vehicle Spawn Control MOD 完整說明：面板操作與設定檔 -->
<!-- 摘要：Minidoracat 車輛生成控制 MOD 的圖文說明：用遊戲內面板調整各區域的生成數量與車型比例、3D 預覽與塗裝、批次調整、變更紀錄與還原，以及權限、設定檔格式、已知限制與常見問題。 -->
=== 🚀 快速上手
[b]English version:[/b] [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3817839906]Vehicle Spawn Control Mod Guide[/url]

MOD 本體（Steam Workshop）：
https://steamcommunity.com/sharedfiles/filedetails/?id=3812410742

車輛生成控制讓伺服器管理員（或單人玩家）決定：世界生成新車時，各區域生成多少車、生成哪些車。可以在遊戲內面板操作，也可以直接編輯設定檔。
[list]
[*] [b]必要前置[/b]：一併訂閱 [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3789836701]Minidoracat UI Library[/url]。
[*] [b]多人遊戲[/b]：需要伺服器啟用本 MOD。
[/list]
[olist]
[*] [b]打開面板[/b]：
[list]
[*] 多人：具備「沙盒設定」權限的管理員打開原版管理面板，按最後一格「車輛生成控制」。
[*] 單人：在地上按右鍵，選「車輛生成控制」。
[/list]
[*] [b]調整[/b]：在「車輛」或「區域」分頁調整。
[*] [b]套用[/b]：按「套用變更」。之後才生成的區塊會照新設定，已經生成的車不會變。
[/olist]
{{img:05-pending-changes-zh.jpg}}
[list]
[*] [b]不想進遊戲也行[/b]：直接編輯設定檔 config.json，存檔後約一分鐘內自動生效（位置見「設定檔位置與同步」）。
[/list]
=== 🧰 自動收錄車輛
[list]
[*] [b]不必手動登記[/b]：開服時讀取所有車輛與各區域的車輛分布，原版與 MOD 新增的車都會列出。
[*] [b]來源 MOD[/b]：依遊戲實際載入車輛的紀錄判斷，不看車名前綴。
[*] [b]被覆寫的原版車[/b]：仍算原版，並列出覆寫它的 MOD。
[*] [b]變體自動成組[/b]：同名的變體（同一款車的燒毀版、撞爛版等）收成一組，可以整組調整。
[*] [b]新偵測[/b]：首次安裝本 MOD 之後才出現的車會標示「新偵測」，可以設定讓它們先不生成（見「config.json 欄位」的 newVehicles）。
[/list]
=== 🧰 生成數量與車型比例
{{img:04-zone-composition-zh.jpg}}
[h3]調整生成數量[/h3]
[list]
[*] [b]每格生成機率[/b]：在「區域」分頁調整，決定這個區域的停車格有多少會生車。
[*] [b]其他機率與車況[/b]：一般車、燒毀車、特殊車、零件損壞、附鑰匙的機率與車況，也可以調。
[*] [b]沙盒的「車輛產生率」[/b]：仍然有效，會再乘上每格生成機率；面板會顯示目前的沙盒值。
[/list]
[h3]調整車型比例[/h3]
[list]
[*] [b]整包倍率[/b]：在「車輛」分頁選一個來源（原版或某個 MOD），一次讓它所有的車在所有區域變多或變少；設為 0 等於整包停用。
[*] [b]單車倍率與停用[/b]：選一台車，可以設定「所有區域倍率」，或在所有區域停用它。
[*] [b]區域權重[/b]：在「區域」分頁調某區每台車的權重，也可以把車加進原本沒有它的區域；權重 0 會從這區移除。
[*] [b]生成塗裝[/b]：可以指定某區生成某台車時用第幾款塗裝，或維持隨機。
[/list]
[h3]權重怎麼算[/h3]
[list]
[*] [b]實際權重[/b]＝區域權重 × 車款倍率 × 來源倍率。
[*] [b]相對比例[/b]：權重是同一區內的相對比例。調低某個來源，其他車的占比會上升，但這區生成的車總數不變（總數由每格生成機率決定）。
[*] [b]對照原本占比[/b]：占比和原本不同時，會同時顯示原本的占比（例如「原 17.8%　9.4%」），方便看出調整幅度。
[/list]
=== 🧰 3D 預覽與塗裝色票
{{img:01-vehicle-preview-zh.jpg}}
[h3]操作[/h3]
[list]
[*] [b]滑鼠[/b]：左鍵拖曳旋轉、右鍵拖曳平移、滾輪縮放、雙擊重設。
[*] [b]按鈕[/b]：正面、側面、俯視。
[/list]
[h3]塗裝色票[/h3]
{{img:02-paint-swatches-zh.jpg}}
[list]
[*] [b]切換塗裝[/b]：多塗裝的車會在預覽下方列出每款塗裝的貼圖色票，點色票就把 3D 預覽換成那款塗裝，原版車和 MOD 車都可以。
[*] [b]外框[/b]：目前選的那款有強調色外框，滑鼠移上去只會標亮外框。
[*] [b]車色固定[/b]：這是遊戲內建引擎的限制，不是本 MOD 自製的預覽：遊戲內建的 3D 預覽元件只用固定的車色。實際生成的車不受影響，照常隨機上色。
[/list]
[h3]額外零件與選配零件[/h3]
[list]
[*] [b]額外零件模型[/b]：遊戲內建的 3D 預覽元件每個零件只畫第一個模型；有額外零件模型的 MOD 車（例如 '87 Ford B700 校車、軍用與監獄巴士的車頂，KI5 '85 Chevrolet Step-Van SWAT 的警示燈架），面板會讓遊戲內建的預覽一起畫出，位置和塗裝都正確。
[*] [b]選配零件[/b]：預覽會畫出所有選配零件（裝甲、車頂架、備胎等），實際生成的車照車輛 MOD 自己的規則裝配。
[/list]
[h3]每次進遊戲 64 組[/h3]
[list]
[*] [b]上限[/b]：每次進遊戲，面板可以預覽 64 組「車＋塗裝」。
[*] [b]會用掉一組[/b]：第一次看某台車的非預設塗裝，或第一次看需要畫出額外零件的 MOD 車。
[*] [b]不計算[/b]：切回看過的組合、以預設塗裝瀏覽車款（以及沒有額外零件的原版車）。
[*] [b]用完後[/b]：新的塗裝會在預覽區以平面貼圖顯示，部分零件可能缺少，面板會註明。
[*] [b]重置[/b]：回主選單或重新連線。
[/list]
[h3]沒有 3D 預覽的車[/h3]
[list]
[*] [b]原因[/b]：有些 MOD 會替車加上沒有模型的輪胎零件（例如 Immersive Snow 0.5.2 初版，作者已在 Patch 1 修好），遊戲內建的 3D 預覽元件遇到這種車會出錯。
[*] [b]面板的處理[/b]：偵測到時不顯示這台車的 3D 預覽，並在預覽下方註明。
[*] [b]其他照常[/b]：面板其他功能照常，實際生成的車不受影響。
[/list]
=== 🧰 批次調整
{{img:03-batch-edit-zh.jpg}}
[h3]車輛清單[/h3]
[list]
[*] [b]多選[/b]：Ctrl 加選、Shift 選一段、勾選框全選。
[*] [b]批次操作[/b]：選了兩台以上，右欄會變成批次操作：
[list]
[*] 設定倍率
[*] 加入或移出區域
[*] 在所有區域停用或啟用
[/list]
[/list]
[h3]區域分頁的車款表[/h3]
[list]
[*] [b]多選[/b]：同樣支援點選、Ctrl／Shift 多選與全選。
[*] [b]一起調整[/b]：減半、加倍、設定權重、移出此區域或還原。
[*] [b]依來源選取[/b]：點組成長條上的來源，可以直接選取它在這區的所有車。
[/list]
=== 🧰 變更紀錄與還原
{{img:06-change-history-zh.jpg}}
[list]
[*] [b]每次套用都記下[/b]：修訂號、時間、來源（面板、設定檔、開服或還原）、誰改的，以及改了哪些項目。
[*] [b]重啟不另記[/b]：伺服器重啟時設定沒變，不會另記一筆。
[*] [b]還原[/b]：可以還原到最近 10 次生效過的任一版本。
[*] [b]關服期間的修改[/b]：伺服器關閉期間有人直接改過設定檔，下次開服也會列出差異。
[/list]
=== ⚙️ 權限
[list]
[*] [b]多人[/b]：沿用原版角色的「沙盒設定」權限（預設版主與管理員有，GM 沒有）。
[*] [b]給其他角色[/b]：管理員可以在角色設定把這個權限給任何角色。
[*] [b]伺服器端檢查[/b]：每個寫入命令都會再檢查一次。
[*] [b]單人[/b]：不檢查權限。
[/list]
=== ⚙️ 設定檔位置與同步
設定檔在 Zomboid 資料夾的 [b]Lua/MinidoracatVehicleSpawnControl/[/b]：
[list]
[*] [b]專用伺服器[/b]：伺服器主機的 Zomboid/Lua/MinidoracatVehicleSpawnControl/（啟動參數有指定 -cachedir 時，改用該目錄）
[*] [b]開房合作（Co-op）與單人[/b]：開房玩家本機的 %USERPROFILE%/Zomboid/Lua/MinidoracatVehicleSpawnControl/
[/list]
[h3]資料夾裡的檔案[/h3]
[table]
[tr][th]檔案[/th][th]用途[/th][/tr]
[tr][td]config.json[/td][td]你編輯的設定，只記和原本不同的地方[/td][/tr]
[tr][td]catalog.json（唯讀）[/td][td]所有車款、來源 MOD、出現在哪些區域與實際占比；要填車款名或區域名時照這份抄[/td][/tr]
[tr][td]status.json（唯讀）[/td][td]最近一次檢查是否成功、錯誤、警告與新偵測的車[/td][/tr]
[tr][td]history.json、backups/[/td][td]變更紀錄與最近 10 份生效設定的備份[/td][/tr]
[tr][td]state.json[/td][td]內部狀態，不要手動修改[/td][/tr]
[/table]
[h3]設定檔同步[/h3]
[list]
[*] [b]檢查頻率[/b]：每分鐘檢查一次 config.json，內容有變才重新讀取；成功就套用並更新 status.json。
[*] [b]沒人時暫停[/b]：伺服器設定「沒人時暫停」（PauseEmpty，預設開啟）時，沒有玩家在線就不會檢查，要等有人上線。
[*] [b]寫錯時[/b]：整份拒絕、保留原本生效的設定，並在 status.json 與面板的「設定檔同步」分頁寫出第幾行或哪個欄位、該怎麼改。
[*] [b]同時編輯[/b]：有人在你編輯面板時改了設定檔，按套用前會先詢問要不要覆寫。
[/list]
=== ⚙️ config.json 欄位
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
[table]
[tr][th]欄位[/th][th]填法[/th][/tr]
[tr][td]newVehicles[/td][td]"keep" 照各 MOD 自己的比例；"disable" 讓新偵測的車先不生成，要在 vehicles 裡寫 "enabled": true 才開[/td][/tr]
[tr][td]sources[/td][td]來源 MOD 的 ID 對應倍率；原版是 pz-vanilla[/td][/tr]
[tr][td]vehicles[/td][td]完整車款名（Module.Script）對應 "enabled"（true／false）與 "multiplier"（≥ 0）[/td][/tr]
[tr][td]zones[/td][td]區域名對應區域參數、weights 與 skins[/td][/tr]
[tr][td]weights[/td][td]權重 ≥ 0；0 會從這區移除，也可以加入原本沒有的車[/td][/tr]
[tr][td]skins[/td][td]塗裝序號，-1 是隨機[/td][/tr]
[/table]
[h3]區域參數[/h3]
[table]
[tr][th]參數[/th][th]範圍[/th][/tr]
[tr][td]spawnRate、chanceToSpawnNormal、chanceToSpawnBurnt、chanceToSpawnSpecial、chanceToPartDamage、chanceToSpawnKey[/td][td]0–100[/td][/tr]
[tr][td]baseVehicleQuality[/td][td]0–2[/td][/tr]
[/table]
[h3]注意事項[/h3]
[list]
[*] [b]區域名[/b]：要和 catalog.json 完全相同，大小寫也算。
[*] [b]business 的別名[/b]：business2 到 business12 是 business 的別名，請寫 business。
[*] [b]已移除的車或區域[/b]：只會列成警告，不會擋下整份設定。
[*] [b]不殘留[/b]：每次套用都從開服時的原始分布重算，舊設定不會殘留。
[/list]
=== ⚠️ 已知限制
[list]
[*] [b]只影響新區塊[/b]：只影響之後第一次生成的區塊；已經生成過的區塊不會重抽。
[*] [b]隨機事件[/b]：部分隨機事件會直接指定車型（例如某些車禍現場），不經區域分布，本 MOD 管不到。
[*] [b]3D 預覽車色[/b]：受遊戲內建引擎限制，車色固定（實際生成不受影響）。
[*] [b]3D 預覽數量[/b]：每次進遊戲最多預覽 64 組「車＋塗裝」，用完後新的塗裝以平面貼圖呈現，回主選單或重新連線就重置。
[*] [b]選配零件[/b]：3D 預覽會畫出所有選配零件（實際生成照車輛 MOD 自己的規則裝配）。
[*] [b]沒有模型的輪胎零件[/b]：其他 MOD 替車加了這種零件時，這台車沒有 3D 預覽（實際生成不受影響）。
[*] [b]設定檔共用[/b]：設定檔放在使用者資料夾，同一個資料夾下的所有單人存檔與自架伺服器共用同一份設定。
[*] [b]沒人時暫停[/b]：伺服器設定「沒人時暫停」（PauseEmpty）時，沒有玩家在線的期間伺服器整個暫停，設定檔要等有人上線後才會套用；這是遊戲本身的行為。
[/list]
=== ❓ 常見問題
[h3]改了設定，路上的車沒變？[/h3]
[list]
[*] 設定只影響之後新生成的區塊，到還沒去過的地方看。
[/list]
[h3]權重調高了，車的總數卻沒變多？[/h3]
[list]
[*] 權重是區內的相對比例。
[*] 要讓車變多，調每格生成機率或沙盒的車輛產生率。
[/list]
[h3]3D 預覽怎麼換塗裝？車色為什麼固定？[/h3]
[list]
[*] [b]換塗裝[/b]：點預覽下方的色票。
[*] [b]車色固定[/b]：是遊戲內建引擎的限制，遊戲內建的 3D 預覽元件只用固定的車色；實際生成的車照常隨機上色。
[*] [b]64 組上限[/b]：遊戲內建引擎沒有提供刪除車種或直接更換預覽塗裝的方法，面板只能把車載入本 MOD 內附的 64 個預覽專用車種，所以每次進遊戲最多預覽 64 組「車＋塗裝」；用完後新的塗裝以平面貼圖顯示，回主選單或重新連線就重置。
[/list]
[h3]管理員生車清單的「burnt」篩選裡出現 MVSCPreview.PreviewBurnt01～64？[/h3]
[list]
[*] [b]是什麼[/b]：本 MOD 的 3D 預覽專用車種，只在各玩家自己電腦的記憶體裡使用，不存檔、不經網路傳送，也不在任何生成區域、catalog.json 或設定檔裡。
[*] [b]不會留在世界上[/b]：從清單生出一台的話，伺服器會立刻把它換成其他沒有輪子的車種（多半是燒毀車）。伺服器移除某個車輛 MOD 後，遊戲會把那個 MOD 留下的車換成隨機車種（沒有輪子的車種只會替換燒毀車），萬一抽到預覽車種，也會在車輛加入世界時立刻換成一般車種。
[*] [b]備援[/b]：預覽車種本身定義成原版燒毀轎車的車殼，只作為備援。
[/list]
[h3]想讓某個 MOD 的車少一點？[/h3]
[list]
[*] 「車輛」分頁選那個 MOD，調低整包倍率。
[/list]
[h3]設定檔改了沒生效？[/h3]
[list]
[*] 看 status.json 或面板「設定檔同步」分頁列出的錯誤；寫錯時會保留原本的設定。
[*] 伺服器沒有玩家在線、又設定了「沒人時暫停」的話，要等有人上線才會套用。
[/list]
[h3]剛裝了新的車輛 MOD，不想它馬上出現？[/h3]
[list]
[*] 把 newVehicles 設成 "disable"，確認後再逐台開啟。
[/list]
[h3]和其他會改車輛分布的 MOD 一起用？[/h3]
[list]
[*] 開服前改好分布的 MOD 會被正常收錄。
[*] 開服之後才改分布的，改動會在本 MOD 下次套用時被覆蓋。
[/list]
[h3]移除本 MOD 會怎樣？[/h3]
[list]
[*] 車輛分布回到原版與各 MOD 的設定。
[*] 已經生成的車留在世界上。
[*] 設定檔留在資料夾裡，不影響存檔。
[/list]
=== 💬 回報方式
[list]
[*] [b]回報管道[/b]：
[list]
[*] [url=https://github.com/Minidoracat/MinidoracatVehicleSpawnControlFor42/issues]GitHub Issues[/url]
[*] [url=https://discord.gg/Gur2V67]Discord[/url]
[/list]
[*] [b]回報時請附上[/b]：
[list]
[*] status.json
[*] 伺服器 log（server-console.txt；單人是 console.txt）裡以 [MinidoracatVehicleSpawnControlFor42] 開頭的幾行
[/list]
[/list]
