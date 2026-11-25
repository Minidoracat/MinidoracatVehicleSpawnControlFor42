[h1]Minidoracat Vehicle Spawn Control for B42 42.22.2-0.5.0[/h1]
[i]2026-11-10[/i]

[b]English summary[/b]
[list]
[*] New "Spawn near me" button in the Vehicles tab: pick one vehicle and a paint, and the panel places it on open ground within 12 tiles of you, fully repaired with the key in the ignition. You get exactly the model you picked; it is not swapped for a local variant.
[*] Works in singleplayer right away. In multiplayer you also need the vanilla ManipulateVehicle permission (the one /addvehicle uses); the server checks it every time.
[*] Supports Project Zomboid 42.22.2. Re-tested in singleplayer and on multiplayer servers; no settings need to change.
[*] Parking lot refill no longer puts very long modded trailers into spots they do not fit.
[/list]

[h3]✨ 新增[/h3]
[list]
[*] [b]管理面板可以把車直接生成到身邊[/b]：車輛分頁只選一台車時，中間欄下方多一顆「生成到身邊」，按下去會在你身邊 12 格內找一塊放得下這台車的戶外空地，放一台目前預覽的車款與塗裝。車況和原版管理員生車一樣：全部修好、鑰匙插在車上、駕駛座車門沒鎖；車色照常隨機。原版生車會把壁畫廂型車、警車這類車款換成當地的版本，這裡不換，生出來的就是你選的那一款。車不會放進室內，不會卡在牆、圍籬、門窗、車庫門或樓梯上，不會壓到其他車或貼著你，連按也不會疊在一起。不在地面那一層（樓上或地下室）、附近沒有空地或沒有權限時，面板下方會說明原因；多人伺服器上剛傳送或剛走到一個地方時，要等幾秒讓附近原有的車載入完才放得下，面板也會提示。單人直接可用；多人除了要能開這個面板，還要有原版生車用的「ManipulateVehicle」權限（預設版主與管理員都有）
[/list]

[h3]🔄 變更[/h3]
[list]
[*] [b]支援 Project Zomboid 42.22.2[/b]：在 42.22.2 的單人與多人伺服器重新驗過面板、3D 預覽、設定檔同步、停車場補車與權限檢查，更新後不用改任何設定
[*] Server config files saved as "UTF-8 with BOM" (Notepad, Windows PowerShell 5.1, some editors) now load normally. Before, the whole file was treated as broken: the server started with the vanilla spawn mix and ignored later edits.
[/list]

[h3]🔧 修正[/h3]
[list]
[*] [b]停車場補車：車身很長的 MOD 拖車可能補進放不下的車位[/b]：0.4.0 起，補車檢查車位周圍有沒有東西擋住時，少算了這類拖車往一頭多伸出去的那一段（例如 11 格長的貨櫃拖車，約 3 格），車尾可能壓到車位外的東西。現在補車和「生成到身邊」一樣把這一段算進去，放不下就不補。原版車幾乎不受影響：只有小拖車與旅行車的檢查範圍每邊多了不到半格
[/list]
