<!-- Steam discussion post source (English); the description is a summary, this thread is the full reference -->
<!-- Thread URL: https://steamcommunity.com/workshop/filedetails/discussion/3812410742/586187704184634439/ -->
<!-- Title: 📖 Vehicle Spawn Control Guide: Panel & Config File -->

[b]繁體中文版：[/b] [url=https://steamcommunity.com/workshop/filedetails/discussion/3812410742/586187704184634450/]Vehicle Spawn Control 完整說明：面板操作與設定檔[/url]

Vehicle Spawn Control lets server admins (or singleplayer players) decide how many vehicles spawn in each zone and which ones, whenever the world generates new vehicles. You can use the in-game panel or edit the config file directly. This thread covers every feature, the config file format, known limitations and FAQ.

[h2]🚀 Quick start[/h2]
[list]
[*] Also subscribe to the required [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3789836701]Minidoracat UI Library for B42[/url]; in multiplayer the server must enable this mod.
[/list]
[olist]
[*] Multiplayer: an admin with the Sandbox Options permission opens the vanilla Admin Panel and clicks the last button, "Vehicle Spawn Control".
[*] Singleplayer: right-click the ground and choose "Vehicle Spawn Control".
[*] Make changes on the Vehicles or Zones tab and press "Apply changes". Areas generated from then on follow the new settings; vehicles already in the world stay as they are.
[*] Rather not open the game? Edit config.json and save it; it applies within about a minute (location under "Config file" below).
[/olist]

[h2]✨ Features in detail[/h2]
[h3]Automatic vehicle list[/h3]
[list]
[*] At startup the mod reads every vehicle and each zone's vehicle distribution, so vanilla vehicles and vehicles added by mods all show up without any manual setup.
[*] The source mod comes from the game's own record of which mod loaded each vehicle, not from the name prefix. A vanilla vehicle overridden by a mod still counts as vanilla and lists the mod that overrides it.
[*] Variants with the same name (burnt or wrecked versions of one model, for example) are grouped so you can adjust them together.
[*] Vehicles that first appear after this mod was installed are marked "New", and you can keep them from spawning until you approve them (see newVehicles in the config file).
[/list]

[h3]Spawn amount[/h3]
[list]
[*] The Zones tab sets each zone's per-slot spawn chance, which decides how many of the zone's parking slots get a vehicle.
[*] You can also change the odds of normal, burnt and special vehicles, part damage, keys, and the vehicle condition.
[*] The sandbox "Vehicle Spawn Rate" still applies on top of the per-slot chance; the panel shows the current sandbox value.
[/list]

[h3]Vehicle mix[/h3]
[list]
[*] [b]Pack multiplier[/b]: on the Vehicles tab, pick a source (vanilla or a mod) to make all of its vehicles more or less common in every zone at once; 0 disables the whole pack.
[*] [b]Per-vehicle multiplier and disable[/b]: pick a vehicle to set its all-zones multiplier, or disable it everywhere.
[*] [b]Zone weights[/b]: on the Zones tab, change each vehicle's weight in a zone, or add a vehicle to a zone that never had it; weight 0 removes it from that zone.
[*] [b]Spawn paint[/b]: choose which paint job a vehicle uses when it spawns in a zone, or keep it random.
[*] Effective weight = zone weight × vehicle multiplier × source multiplier. Weights are relative within a zone: lowering one source raises everyone else's share, but the zone's total number of vehicles stays the same (the per-slot spawn chance sets the total).
[*] When a share differs from the original, the original share is shown next to it, so you can see how much you changed.
[/list]

[h3]3D preview and paint swatches[/h3]
[list]
[*] Left-drag to rotate, right-drag to pan, scroll to zoom, double-click to reset; front, side and top buttons are there too.
[*] The preview always shows the first paint job and the default color. This is a limit of the game's built-in engine, not of a preview made by this mod: the game's built-in 3D preview only loads each vehicle's first paint job and offers no way to switch it. Spawned vehicles are not affected and still use every paint job. Vehicles with several paint jobs list a texture swatch for each one under the preview; hover a swatch to enlarge it.
[*] The game's built-in 3D preview only draws the first model of each vehicle part, so some modded vehicles lose their roof or interior there; the panel draws those models in. A few body-colored parts still can't be drawn because of the game's built-in engine, and the preview says so underneath. The preview also shows every optional part (armor, roof racks, spare tires and so on); spawned vehicles are equipped by the vehicle mod's own rules.
[*] Some mods give vehicles wheel parts without a model (Immersive Snow 0.5.2, for example), and the game's built-in 3D preview errors out on them; the panel detects this, skips the 3D preview for that vehicle and says so underneath. The rest of the panel keeps working and spawned vehicles are not affected.
[/list]

[h3]Batch edits[/h3]
[list]
[*] The vehicle list supports multi-select: Ctrl adds, Shift selects a range, the checkbox selects all. With two or more selected, the right column turns into batch actions: set a multiplier, add to or remove from zones, disable or enable in every zone.
[*] The Zones tab's vehicle table supports click, Ctrl/Shift multi-select and select-all too, for halving, doubling, setting weights, removing from the zone or restoring. Click a source in the composition bar to select all of its vehicles in that zone.
[/list]

[h3]Config file sync[/h3]
[list]
[*] config.json is checked once a minute and only re-read when its content changed; a valid file is applied and status.json is updated. If the server option PauseEmpty is on (the default), nothing is checked while no player is online; it waits until someone joins.
[*] A mistake rejects the whole file and keeps the settings that were already in effect; status.json and the panel's Config file tab show the line or field and how to fix it.
[*] If someone edits the file while you are editing in the panel, you are asked before your changes overwrite it.
[/list]

[h3]History and restore[/h3]
[list]
[*] Every apply records the revision, time, source (panel, config file, startup or restore), who made it and what changed. A restart with unchanged settings does not add an entry.
[*] You can restore any of the last 10 revisions that were in effect.
[*] Edits made to the config file while the server was offline are listed at the next startup.
[/list]

[h3]Permissions[/h3]
[list]
[*] Multiplayer: uses the vanilla role permission "Sandbox Options" (moderators and admins have it by default, GMs do not). Admins can grant it to any role in the role settings, and the server checks it again on every write command.
[*] Singleplayer: no permission check.
[/list]

[h2]⚙️ Config file[/h2]
The files live in the Zomboid folder under [b]Lua/MinidoracatVehicleSpawnControl/[/b]:
[list]
[*] [b]Dedicated server[/b]: Zomboid/Lua/MinidoracatVehicleSpawnControl/ on the server host (or under the -cachedir folder if the server is started with one)
[*] [b]Co-op host and singleplayer[/b]: %USERPROFILE%/Zomboid/Lua/MinidoracatVehicleSpawnControl/ on the hosting player's PC
[/list]
[list]
[*] [b]config.json[/b]: the settings you edit; it only records what differs from the original.
[*] [b]catalog.json[/b] (read-only): every vehicle, its source mod, the zones it appears in and its actual share. Copy vehicle and zone names from here.
[*] [b]status.json[/b] (read-only): whether the last check succeeded, plus errors, warnings and newly detected vehicles.
[*] [b]history.json, backups/[/b]: the change history and backups of the last 10 applied configs.
[*] [b]state.json[/b]: internal state; do not edit it.
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
[*] [b]newVehicles[/b]: "keep" uses each mod's own mix; "disable" keeps newly detected vehicles from spawning until you set "enabled": true for them under vehicles.
[*] [b]sources[/b]: source mod ID to multiplier; vanilla is pz-vanilla.
[*] [b]vehicles[/b]: full vehicle name (Module.Script) to "enabled" (true/false) and "multiplier" (0 or more).
[*] [b]zones[/b]: zone name to zone settings, weights and skins. The zone settings are spawnRate, chanceToSpawnNormal, chanceToSpawnBurnt, chanceToSpawnSpecial, chanceToPartDamage, chanceToSpawnKey (0-100) and baseVehicleQuality (0-2).
[*] [b]weights[/b]: 0 or more; 0 removes the vehicle from that zone, and you can add vehicles the zone never had. [b]skins[/b]: paint job number, -1 for random.
[*] Zone names must match catalog.json exactly, including upper and lower case; business2 to business12 are aliases of business, so write business.
[*] Vehicles or zones that no longer exist only produce a warning and do not block the rest of the file. Every apply is recalculated from the original distribution captured at startup, so old settings never linger.
[/list]

[h2]⚠️ Known limitations[/h2]
[list]
[*] Only areas generated for the first time from now on are affected; areas that already generated keep their vehicles.
[*] Some random events spawn a fixed vehicle type (certain crash scenes, for example) without using the zone distribution, so this mod cannot change them.
[*] Because of a limit in the game's built-in engine, the 3D preview can only show the first paint job and the default color (spawned vehicles are not affected); other paint jobs are shown as texture swatches.
[*] Because of a limit in the game's built-in engine, a few body-colored parts can't be drawn in the 3D preview, and every optional part is shown (spawned vehicles are not affected).
[*] When another mod gives a vehicle wheel parts without a model, that vehicle has no 3D preview (spawned vehicles are not affected).
[*] The config file lives in the user folder, so every singleplayer save and self-hosted server using that folder shares one config.
[*] With the server option PauseEmpty on, the whole server pauses while no player is online, so config file edits only apply once someone joins; this is how the game itself works.
[/list]

[h2]❓ FAQ[/h2]
[list]
[*] [b]I changed the settings but the cars on the road are the same?[/b] Settings only affect areas generated from now on; check a place you have not visited yet.
[*] [b]I raised a weight but the total number of cars did not go up?[/b] Weights are relative within a zone. For more cars, raise the per-slot spawn chance or the sandbox Vehicle Spawn Rate.
[*] [b]Why can't the 3D preview switch paint jobs, and why is the color always the same?[/b] It is a limit of the game's built-in engine: the game's built-in 3D preview only loads each vehicle's first paint job and default color and has no way to switch them. Spawned vehicles are not affected; hover the swatches under the preview to see the other paint jobs.
[*] [b]How do I make one mod's vehicles rarer?[/b] On the Vehicles tab, pick that mod and lower its pack multiplier.
[*] [b]My config edit did not apply?[/b] Check the errors in status.json or on the panel's Config file tab; a mistake keeps the previous settings. If no player is online and PauseEmpty is on, it applies once someone joins.
[*] [b]I just installed a vehicle mod and do not want it to appear yet?[/b] Set newVehicles to "disable", then enable vehicles one by one once you are happy.
[*] [b]Does it work with other mods that change the vehicle distribution?[/b] Changes made before startup are picked up normally. Changes another mod makes after startup are overwritten the next time this mod applies its settings.
[*] [b]What happens if I remove this mod?[/b] The distribution goes back to vanilla and each mod's own settings, vehicles that already spawned stay in the world, and the config folder stays on disk without affecting saves.
[/list]

[h2]💬 Feedback[/h2]
When reporting a problem, please attach status.json and the lines starting with [MinidoracatVehicleSpawnControlFor42] from the server log (server-console.txt; console.txt in singleplayer).
[list]
[*] [url=https://github.com/Minidoracat/MinidoracatVehicleSpawnControlFor42/issues]GitHub Issues[/url]
[*] [url=https://discord.gg/Gur2V67]Discord[/url]
[/list]
