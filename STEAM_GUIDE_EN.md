<!-- 指南網址：https://steamcommunity.com/sharedfiles/filedetails/?id=3817839906 -->
<!-- Steam guide source (English): the full reference for this mod; the Workshop description only summarizes. Format and sync: pz-family-docs/release.md「完整說明：Steam 指南」 -->
<!-- 標題：📖 Vehicle Spawn Control Mod Guide: Panel & Config File -->
<!-- 摘要：Illustrated guide to the Minidoracat Vehicle Spawn Control mod: using the in-game panel to set each zone's spawn amount and vehicle mix, the 3D preview and paint jobs, batch edits, history and restore, parking lot refill, plus permissions, the config file format, known limitations and FAQ. -->
=== 🚀 Quick start
[b]繁體中文版：[/b][url=https://steamcommunity.com/sharedfiles/filedetails/?id=3817839865]車輛生成控制 MOD 完整說明[/url]

The mod on Steam Workshop:
https://steamcommunity.com/sharedfiles/filedetails/?id=3812410742

Vehicle Spawn Control lets server admins (or singleplayer players) decide how many vehicles spawn in each zone and which ones, whenever the world generates new vehicles. You can use the in-game panel or edit the config file directly.
[list]
[*] [b]Required[/b]: also subscribe to [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3789836701]Minidoracat UI Library[/url].
[*] [b]Multiplayer[/b]: the server must enable this mod.
[/list]
[olist]
[*] [b]Open the panel[/b]:
[list]
[*] Multiplayer: an admin with the Sandbox Options permission opens the vanilla Admin Panel and clicks the last button, "Vehicle Spawn Control".
[*] Singleplayer: right-click the ground and choose "Vehicle Spawn Control".
[/list]
[*] [b]Make changes[/b]: on the Vehicles or Zones tab.
[*] [b]Apply[/b]: press "Apply changes". Areas generated from then on follow the new settings; vehicles already in the world stay as they are.
[/olist]
{{img:05-pending-changes-en.jpg}}
[list]
[*] [b]Rather not open the game?[/b] Edit config.json and save it; it applies within about a minute (location under "Config file location & sync").
[/list]
=== 🧰 Automatic vehicle list
[list]
[*] [b]No manual setup[/b]: at startup the mod reads every vehicle and each zone's vehicle distribution, so vanilla vehicles and vehicles added by mods all show up.
[*] [b]Source mod[/b]: comes from the game's own record of which mod loaded each vehicle, not from the name prefix.
[*] [b]Overridden vanilla vehicles[/b]: still count as vanilla and list the mod that overrides them.
[*] [b]Variant groups[/b]: variants with the same name (burnt or wrecked versions of one model, for example) are grouped so you can adjust them together.
[*] [b]New[/b]: vehicles that first appear after this mod was installed are marked "New", and you can keep them from spawning until you approve them (see newVehicles under "config.json fields").
[*] [b]Broken spawn entries[/b]: when a vehicle mod's spawn list names a vehicle that does not exist (a typo, or a mod that is not installed), the server drops the entry at startup and notes it in the server log. Whenever the game picked such an entry, the rest of that parking lot stayed empty.
[*] [b]Zones with capital letters[/b]: the game only looks zones up in lowercase, so vanilla luxuryDealership and middleClass (and some mod zones) never spawned anything. The server adds a lowercase name at startup so the game finds them. The vanilla map does not use these two zones; only custom maps that do will start spawning vehicles there.
[/list]
=== 🧰 Spawn amount & vehicle mix
{{img:04-zone-composition-en.jpg}}
[h3]Spawn amount[/h3]
[list]
[*] [b]Per-slot spawn chance[/b]: set on the Zones tab; it decides how many of the zone's parking slots get a vehicle.
[*] [b]Other odds and condition[/b]: you can also change the odds of normal, burnt and special vehicles, part damage, keys, and the vehicle condition.
[*] [b]Sandbox "Vehicle Spawn Rate"[/b]: still applies on top of the per-slot chance; the panel shows the current sandbox value.
[/list]
[h3]Vehicle mix[/h3]
[list]
[*] [b]Pack multiplier[/b]: on the Vehicles tab, pick a source (vanilla or a mod) to make all of its vehicles more or less common in every zone at once; 0 disables the whole pack.
[*] [b]Per-vehicle multiplier and disable[/b]: pick a vehicle to set its all-zones multiplier, or disable it everywhere.
[*] [b]Zone weights[/b]: on the Zones tab, change each vehicle's weight in a zone, or add a vehicle to a zone that never had it; weight 0 removes it from that zone.
[*] [b]Disabling a whole zone[/b]: when every vehicle in a zone is removed or disabled, the zone spawns nothing at all (no normal, special or burnt vehicles instead), and other zones no longer lose vehicles because of it; the panel shows 0% special and burnt odds for that zone. Odds you set for that zone yourself still apply.
[*] [b]Spawn paint[/b]: choose which paint job a vehicle uses when it spawns in a zone, or keep it random.
[/list]
[h3]How weights work[/h3]
[list]
[*] [b]Effective weight[/b] = zone weight × vehicle multiplier × source multiplier.
[*] [b]Relative within a zone[/b]: lowering one source raises everyone else's share, but the zone's total number of vehicles stays the same (the per-slot spawn chance sets the total).
[*] [b]Original share[/b]: when a share differs from the original, the original share is shown next to it, so you can see how much you changed.
[/list]
=== 🧰 3D preview & paint swatches
{{img:01-vehicle-preview-en.jpg}}
[h3]Controls[/h3]
[list]
[*] [b]Mouse[/b]: left-drag to rotate, right-drag to pan, scroll to zoom, double-click to reset.
[*] [b]Buttons[/b]: front, side and top.
[/list]
[h3]Paint swatches[/h3]
{{img:02-paint-swatches-en.jpg}}
[list]
[*] [b]Switch paint jobs[/b]: vehicles with several paint jobs list a texture swatch for each one under the preview; click a swatch to switch the 3D preview to that paint job, for vanilla and modded vehicles alike.
[*] [b]Border[/b]: the selected paint has an accent border, and hovering only highlights the border.
[*] [b]Fixed color[/b]: this is a limit of the game's built-in engine, not of a preview made by this mod: the game's built-in 3D preview uses a fixed color. Spawned vehicles are not affected and still get random colors.
[/list]
[h3]Extra and optional parts[/h3]
[list]
[*] [b]Extra part models[/b]: the game's built-in 3D preview only draws the first model of each vehicle part. For modded vehicles with extra part models (the school, military and prison bus roofs of the '87 Ford B700, the light bar of the KI5 '85 Chevrolet Step-Van SWAT, for example), the panel has the game's built-in preview draw them too, in the right place and paint.
[*] [b]Optional parts[/b]: the preview shows every optional part (armor, roof racks, spare tires and so on); spawned vehicles are equipped by the vehicle mod's own rules.
[/list]
[h3]64 per game session[/h3]
[list]
[*] [b]Limit[/b]: each game session the panel can preview 64 "vehicle + paint" combinations.
[*] [b]Uses one[/b]: the first time you view a non-default paint job of a vehicle, or the first time you view a modded vehicle whose extra parts need drawing.
[*] [b]Free[/b]: switching back to a combination you already viewed, or browsing vehicles at their default paint (and vanilla vehicles without extra parts).
[*] [b]When used up[/b]: new paint jobs show as a flat texture in the preview area and some parts may be missing; the panel says so.
[*] [b]Reset[/b]: return to the main menu or reconnect.
[/list]
[h3]Vehicles without a 3D preview[/h3]
[list]
[*] [b]Cause[/b]: some mods give vehicles wheel parts without a model (the first release of Immersive Snow 0.5.2, for example; its author fixed it in Patch 1), and the game's built-in 3D preview errors out on them.
[*] [b]What the panel does[/b]: detects this, skips the 3D preview for that vehicle and says so underneath.
[*] [b]Everything else works[/b]: the rest of the panel keeps working and spawned vehicles are not affected.
[/list]
=== 🧰 Batch edits
{{img:03-batch-edit-en.jpg}}
[h3]Vehicle list[/h3]
[list]
[*] [b]Multi-select[/b]: Ctrl adds, Shift selects a range, the checkbox selects all.
[*] [b]Batch actions[/b]: with two or more selected, the right column turns into batch actions:
[list]
[*] Set a multiplier
[*] Add to or remove from zones
[*] Disable or enable in every zone
[/list]
[/list]
[h3]Zones tab vehicle table[/h3]
[list]
[*] [b]Multi-select[/b]: click, Ctrl/Shift multi-select and select-all work here too.
[*] [b]Edit together[/b]: halve, double, set weights, remove from the zone or restore.
[*] [b]Select by source[/b]: click a source in the composition bar to select all of its vehicles in that zone.
[/list]
=== 🧰 History & restore
{{img:06-change-history-en.jpg}}
[list]
[*] [b]Every apply is recorded[/b]: the revision, time, source (panel, config file, startup or restore), who made it and what changed.
[*] [b]Restarts[/b]: a restart with unchanged settings does not add an entry.
[*] [b]Restore[/b]: you can restore any of the last 10 revisions that were in effect.
[*] [b]Offline edits[/b]: edits made to the config file while the server was offline are listed at the next startup.
[/list]
=== 🧰 Parking lot refill (off by default)
Vanilla only spawns vehicles the first time an area generates: once players drive cars away, wreck them or strip them, that spot stays empty. With refill on, parking lots that players have visited but nobody has been near for a long time slowly get back the vanilla average number of vehicles.
[list]
[*] [b]Turning it on[/b]: on panel page 3 "Refill", press "On" and then "Apply changes", or add respawn to config.json (see "config.json fields"). No server restart needed.
[*] [b]How long nobody must be there[/b]: 168 hours (7 days) by default, in real time, whatever the day length is; time with the server shut down or paused while empty also counts. A lot is refilled only if it had been empty that long before players came near this time, and only once per visit.
[*] [b]How many vehicles[/b]: each block (64×64 tiles) is filled up to the vanilla average, counting the cars already there, so not every spot gets a car. For example, at the default sandbox Vehicle Spawn Rate a regular parking spot has a car about 17% of the time, so 10 spots get 1 or 2 cars. "Refill up to this share" can be set from 10% to 100% of the vanilla average.
[*] [b]Only places someone has visited[/b]: lots nobody ever saw still have their original cars, so they are skipped. "Visited" means the game's own record for that area, or a player coming near after refill was turned on.
[*] [b]Where it never refills[/b]: anywhere players can see (within about 88 tiles of any player in multiplayer, 40 in singleplayer), around safehouses (10 tiles by default, plus half the car's length), where players have built something, and spots blocked by a vehicle, item, corpse, wall, tree or water.
[*] [b]What gets added[/b]: vehicle types are drawn from that zone's spawn list (burnt and special vehicles included); condition, rust, fuel and alarms follow vanilla odds.
[*] [b]It only adds vehicles[/b]: no vehicle already in the world is deleted, moved or repaired; vehicles managed by ownership or vehicle-claim mods are untouched, and the new cars are ordinary unowned vehicles to them.
[*] [b]Right after turning it on[/b]: recording starts at that moment; places without enough record yet use the game's own "last seen" game time, converted with the day length, so lots long left alone can be refilled on day one. On a multiplayer server the game only records that time when a player sees inside a building, so an outdoor lot whose nearby buildings nobody looked into has no record: it is refilled only after someone visits it once with refill on and then nobody comes near for the threshold. Turning refill off clears the record, and turning it back on starts over.
[*] [b]Player footprints stay on the server[/b]: the record lives in a folder on the server and players cannot request it; the panel only shows totals (vehicles added, where the latest refills were, why spots were skipped last time).
[/list]
=== ⚙️ Permissions
[list]
[*] [b]Multiplayer[/b]: uses the vanilla role permission "Sandbox Options" (moderators and admins have it by default, GMs do not).
[*] [b]Other roles[/b]: admins can grant it to any role in the role settings.
[*] [b]Server check[/b]: the server checks it again on every write command.
[*] [b]Singleplayer[/b]: no permission check.
[/list]
=== ⚙️ Config file location & sync
The files live in the Zomboid folder under [b]Lua/MinidoracatVehicleSpawnControl/[/b]:
[list]
[*] [b]Dedicated server[/b]: Zomboid/Lua/MinidoracatVehicleSpawnControl/ on the server host (or under the -cachedir folder if the server is started with one)
[*] [b]Co-op host and singleplayer[/b]: %USERPROFILE%/Zomboid/Lua/MinidoracatVehicleSpawnControl/ on the hosting player's PC
[/list]
[h3]Files in the folder[/h3]
[table]
[tr][th]File[/th][th]What it is[/th][/tr]
[tr][td]config.json[/td][td]The settings you edit; it only records what differs from the original[/td][/tr]
[tr][td]catalog.json (read-only)[/td][td]Every vehicle, its source mod, the zones it appears in and its actual share. Copy vehicle and zone names from here[/td][/tr]
[tr][td]status.json (read-only)[/td][td]Whether the last check succeeded, plus errors, warnings and newly detected vehicles[/td][/tr]
[tr][td]history.json, backups/[/td][td]The change history and backups of the last 10 applied configs[/td][/tr]
[tr][td]respawn/<world name>/[/td][td]The refill record of where players have been (only which blocks were visited and when); do not edit it[/td][/tr]
[tr][td]state.json[/td][td]Internal state; do not edit it[/td][/tr]
[/table]
[h3]Config file sync[/h3]
[list]
[*] [b]How often[/b]: config.json is checked once a minute and only re-read when its content changed; a valid file is applied and status.json is updated.
[*] [b]PauseEmpty[/b]: if this server option is on (the default), nothing is checked while no player is online; it waits until someone joins.
[*] [b]Mistakes[/b]: a mistake rejects the whole file and keeps the settings that were already in effect; status.json and the panel's Config file tab show the line or field and how to fix it.
[*] [b]Editing at the same time[/b]: if someone edits the file while you are editing in the panel, you are asked before your changes overwrite it.
[/list]
=== ⚙️ config.json fields
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
  },
  "respawn": { "enabled": true, "unseenHours": 168, "density": 100, "safehouseMargin": 10 }
}
[/code]
[table]
[tr][th]Field[/th][th]What to write[/th][/tr]
[tr][td]newVehicles[/td][td]"keep" uses each mod's own mix; "disable" keeps newly detected vehicles from spawning until you set "enabled": true for them under vehicles[/td][/tr]
[tr][td]sources[/td][td]Source mod ID to multiplier; vanilla is pz-vanilla[/td][/tr]
[tr][td]vehicles[/td][td]Full vehicle name (Module.Script) to "enabled" (true/false) and "multiplier" (0 or more)[/td][/tr]
[tr][td]zones[/td][td]Zone name to zone settings, weights and skins[/td][/tr]
[tr][td]weights[/td][td]0 or more; 0 removes the vehicle from that zone, and you can add vehicles the zone never had[/td][/tr]
[tr][td]skins[/td][td]Paint job number, -1 for random[/td][/tr]
[tr][td]respawn[/td][td]Parking lot refill: enabled (default false), unseenHours real hours nobody was near before refilling (default 168, 1–8760), density refill up to this % of the vanilla average (default 100, 10–100), safehouseMargin no refill within this many tiles of a safehouse (default 10, whole numbers 0–50); missing fields use the defaults[/td][/tr]
[/table]
[h3]Zone settings[/h3]
[table]
[tr][th]Setting[/th][th]Range[/th][/tr]
[tr][td]spawnRate, chanceToSpawnNormal, chanceToSpawnBurnt, chanceToSpawnSpecial, chanceToPartDamage, chanceToSpawnKey[/td][td]0-100[/td][/tr]
[tr][td]baseVehicleQuality[/td][td]0-2[/td][/tr]
[/table]
[h3]Notes[/h3]
[list]
[*] [b]Zone names[/b]: must match catalog.json exactly, including upper and lower case. Zones with capital letters also get a lowercase alias at startup (for example luxurydealership); write the original name.
[*] [b]business aliases[/b]: business2 to business12 are aliases of business, so write business.
[*] [b]Removed vehicles or zones[/b]: only produce a warning and do not block the rest of the file.
[*] [b]Nothing lingers[/b]: every apply is recalculated from the original distribution captured at startup, so old settings never linger.
[/list]
=== ⚠️ Known limitations
[list]
[*] [b]New areas only[/b]: only areas generated for the first time from now on are affected; areas that already generated keep their vehicles.
[*] [b]Random events[/b]: some random events spawn a fixed vehicle type (certain crash scenes, for example) without using the zone distribution, so this mod cannot change them.
[*] [b]3D preview color[/b]: because of a limit in the game's built-in engine, the 3D preview color is fixed (spawned vehicles are not affected).
[*] [b]3D preview count[/b]: each game session can preview up to 64 "vehicle + paint" combinations, after which new paint jobs show as a flat texture until you return to the main menu or reconnect.
[*] [b]Optional parts[/b]: the 3D preview shows every optional part (spawned vehicles are equipped by the vehicle mod's own rules).
[*] [b]Wheel parts without a model[/b]: when another mod gives a vehicle such parts, that vehicle has no 3D preview (spawned vehicles are not affected).
[*] [b]Shared config[/b]: the config file lives in the user folder, so every singleplayer save and self-hosted server using that folder shares one config.
[*] [b]PauseEmpty[/b]: with this server option on, the whole server pauses while no player is online, so config file edits only apply once someone joins; this is how the game itself works.
[*] [b]Refill keys[/b]: refilled vehicles come with a key at the game's default 70%, regardless of the zone's key chance.
[*] [b]Refill parking zones[/b]: parking zones drawn as polylines are not refilled; refilled cars sit slightly off-center and at a small angle compared with vanilla spawns.
[*] [b]Refill in singleplayer[/b]: the threshold is real time, so time with the game closed also counts.
[/list]
=== ❓ FAQ
[h3]I changed the settings but the cars on the road are the same?[/h3]
[list]
[*] Settings only affect areas generated from now on; check a place you have not visited yet.
[/list]
[h3]Refill is on, but the parking lot is still empty?[/h3]
[list]
[*] It has not been empty long enough yet (7 days of real time by default), or it was already refilled on this visit.
[*] Refill brings back the vanilla average, not a car in every spot; cars already there count.
[*] Cars are only added where no player can see; the area around you is already loaded when you walk up, so leave for a while and come back.
[*] The panel's "Refill" page lists why spots were skipped last time (player too close, spot blocked, near a safehouse).
[/list]
[h3]I raised a weight but the total number of cars did not go up?[/h3]
[list]
[*] Weights are relative within a zone.
[*] For more cars, raise the per-slot spawn chance or the sandbox Vehicle Spawn Rate.
[/list]
[h3]How do I switch paint jobs in the 3D preview, and why is the color always the same?[/h3]
[list]
[*] [b]Switch paint jobs[/b]: click a swatch under the preview.
[*] [b]Fixed color[/b]: a limit of the game's built-in engine; the game's built-in 3D preview uses a fixed color, and spawned vehicles still get random colors.
[*] [b]64 limit[/b]: the game's built-in engine offers no way to delete vehicle types or change a preview's paint job directly, so the panel loads vehicles into the 64 preview-only vehicle types this mod ships; that is why each game session can preview up to 64 "vehicle + paint" combinations. After that, new paint jobs show as a flat texture until you return to the main menu or reconnect.
[/list]
[h3]What are MVSCPreview.PreviewBurnt01 to 64 under the "burnt" filter of the admin vehicle spawn list?[/h3]
[list]
[*] [b]What they are[/b]: this mod's preview-only vehicle types. Each player's game uses them only in its own memory; they are never saved or sent over the network, and they are not in any spawn zone, catalog.json or the config file.
[*] [b]They never stay in the world[/b]: if you spawn one from the list, the server immediately swaps it for another wheel-less vehicle type (usually a burnt wreck). If a server removes a vehicle mod, the game replaces that mod's leftover vehicles with a random vehicle type (wheel-less types only replace burnt wrecks); if a preview type is picked, it is also swapped for a regular vehicle type the moment the vehicle is added to the world.
[*] [b]Fallback[/b]: each preview type is still defined as a vanilla burnt sedan shell, only as a fallback.
[/list]
[h3]How do I make one mod's vehicles rarer?[/h3]
[list]
[*] On the Vehicles tab, pick that mod and lower its pack multiplier.
[/list]
[h3]My config edit did not apply?[/h3]
[list]
[*] Check the errors in status.json or on the panel's Config file tab; a mistake keeps the previous settings.
[*] If no player is online and PauseEmpty is on, it applies once someone joins.
[/list]
[h3]I just installed a vehicle mod and do not want it to appear yet?[/h3]
[list]
[*] Set newVehicles to "disable", then enable vehicles one by one once you are happy.
[/list]
[h3]Does it work with other mods that change the vehicle distribution?[/h3]
[list]
[*] Changes made before startup are picked up normally.
[*] Changes another mod makes after startup are overwritten the next time this mod applies its settings.
[*] Some vehicle packs define special zones without putting any vehicle in them (for example PZK VLC's highway maintenance, power and phone company zones). Ordinary parking lots no longer pick these empty zones, which used to leave the rest of the lot empty.
[/list]
[h3]What happens if I remove this mod?[/h3]
[list]
[*] The distribution goes back to vanilla and each mod's own settings.
[*] Vehicles that already spawned stay in the world.
[*] The config folder stays on disk without affecting saves.
[/list]
=== 💬 Feedback
[list]
[*] [b]Where to report[/b]:
[list]
[*] [url=https://github.com/Minidoracat/MinidoracatVehicleSpawnControlFor42/issues]GitHub Issues[/url]
[*] [url=https://discord.gg/Gur2V67]Discord[/url]
[/list]
[*] [b]Please attach[/b]:
[list]
[*] status.json
[*] The lines starting with [MinidoracatVehicleSpawnControlFor42] from the server log (server-console.txt; console.txt in singleplayer)
[/list]
[/list]
