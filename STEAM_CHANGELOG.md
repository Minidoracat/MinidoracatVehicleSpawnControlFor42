[h1]Minidoracat Vehicle Spawn Control for B42 42.22.2-0.5.1[/h1]
[i]2026-11-25[/i]

[b]English summary[/b]
[list]
[*] Server config files saved as "UTF-8 with BOM" (Notepad, Windows PowerShell 5.1, some editors) now load normally. Before, the whole file was treated as broken: the server started with the vanilla spawn mix and ignored later edits.
[/list]

[h3]🔧 修正[/h3]
[list]
[*] [b]設定檔存成「UTF-8 含 BOM」時整份設定沒有生效[/b]：從第一版起，用記事本選「UTF-8 with BOM」、Windows PowerShell 5.1 或部分編輯器存的設定檔，開頭會多一個看不見的 BOM 標記，整份設定被當成格式錯誤：伺服器開啟時改用原版的生車分布（你的設定一項都沒套用），執行中改檔則一直保留舊設定。現在會先略過這個標記，照常套用
[/list]
