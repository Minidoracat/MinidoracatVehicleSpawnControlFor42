# -*- coding: utf-8 -*-
"""VehicleSpawnControl 專屬的靜態檢查：scripts/verify_mod.py 第 19 項會呼叫；單獨跑 `python scripts/verify_local.py`。

補車只加車 — MVSC_Respawn*.lua 不得呼叫刪車、移車、修車的 API（permanentlyRemove、removeFromWorld、setX、
              repair、VehiclesDB2…）：補車只用 addVehicleDebug 加車，綁車 MOD 的車不能被動到（設計第 9 節）
"""
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

passed, failed, skipped = [], [], []

# 豁免清單與 verify_mod.py 共用：scripts/verify_ignore.txt，每行一個子字串樣式（# 開頭為註解）。
IGNORE_PATTERNS = []
_ign = os.path.join(os.path.dirname(os.path.abspath(__file__)), "verify_ignore.txt")
if os.path.isfile(_ign):
    with open(_ign, encoding="utf-8") as _fh:
        for _line in _fh:
            _line = _line.strip()
            if _line and not _line.startswith("#"):
                IGNORE_PATTERNS.append(_line)


def ok(label):
    passed.append(label)
    print(f"  PASS  {label}")


def fail(label, details=None):
    details = details or []
    kept = [d for d in details if not any(p in d for p in IGNORE_PATTERNS)]
    waived = [d for d in details if any(p in d for p in IGNORE_PATTERNS)]
    for d in waived:
        print(f"  WAIVE {label}: {d}（verify_ignore.txt 豁免）")
    if not kept:
        if waived:
            ok(f"{label}（{len(waived)} 筆豁免）")
        else:
            ok(label)
        return
    failed.append(label)
    print(f"  FAIL  {label}")
    for d in kept:
        print(f"        {d}")


def find_media():
    hits = []
    mod_root = os.path.join(REPO, "MOD")
    if os.path.isdir(mod_root):
        for folder in os.listdir(mod_root):
            p = os.path.join(mod_root, folder, "Contents", "mods")
            if not os.path.isdir(p):
                continue
            for inner in os.listdir(p):
                media = os.path.join(p, inner, "42", "media")
                if os.path.isdir(media):
                    hits.append(media)
    return hits


def iter_files(root, exts):
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in (".git",)]
        for name in files:
            if os.path.splitext(name)[1] in exts:
                yield os.path.join(base, name)


MEDIA_DIRS = find_media()
if not MEDIA_DIRS:
    print("找不到 MOD/*/Contents/mods/*/42/media，中止")
    sys.exit(2)

LUA_FILES = [f for m in MEDIA_DIRS for f in iter_files(os.path.join(m, "lua"), {".lua"})
             if os.path.isdir(os.path.join(m, "lua"))]
_LONG_COMMENT = re.compile(r"--\[(=*)\[.*?\]\1\]", re.DOTALL)

# ---- 補車只加車：不刪、不移、不修已在世界上的車 ----
# 設計第 9 節與 VLCS 評估報告（2026-10-22）：它的清潔工不分車主與安全屋刪車。補車檔（MVSC_Respawn*.lua）只能用
# addVehicleDebug 加車，之後只改剛加的那台的車況；出現下列呼叫就擋（車輛 MOD 或綁車 MOD 的車會被動到）。
_NO_TOUCH = re.compile(r"(?<!\w)(permanentlyRemove|removeFromWorld|removeFromSquare|removeVehicle|VehiclesDB2|setPosition"
                       r"|setX|setY|teleport\w*|repair|setGeneralPartCondition|sendRemove\w*)\s*\(")
touch_hits = []
for f in LUA_FILES:
    lua_rel = os.path.relpath(f, REPO).replace(os.sep, "/").split("/lua/", 1)[-1]
    if not re.search(r"/MVSC_Respawn\w*\.lua$", lua_rel):
        continue
    with open(f, encoding="utf-8", errors="replace") as fh:
        src = _LONG_COMMENT.sub(lambda mm: "\n" * mm.group().count("\n"), fh.read())
    for lineno, line in enumerate(src.split("\n"), 1):
        mm = _NO_TOUCH.search(line.split("--", 1)[0])
        if mm:
            touch_hits.append(f"{lua_rel}:{lineno} 呼叫 {mm.group(1)}()")
_t = "補車只加車（MVSC_Respawn*.lua 不刪車、不移車、不修車）"
fail(_t, touch_hits) if touch_hits else ok(_t)

sys.exit(1 if failed else 0)
