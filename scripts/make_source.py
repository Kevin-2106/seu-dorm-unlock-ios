#!/usr/bin/env python3
"""生成/更新 SideStore (AltStore 格式) 的源文件 apps.json。

发版时由 CI 调用: 读取已有的 apps.json (如果有)，把新版本放到 versions 最前面，写回。
用户在 SideStore 里添加源 URL 后，就能看到更新提示。
"""
import argparse, json, os
from datetime import datetime, timezone

ap = argparse.ArgumentParser()
ap.add_argument("--repo", required=True)        # Kevin-2106/seu-dorm-unlock-ios
ap.add_argument("--tag", required=True)         # v1.1.0
ap.add_argument("--build", required=True)       # 构建号
ap.add_argument("--size", required=True, type=int)
ap.add_argument("--notes", default="")
ap.add_argument("--out", required=True)
a = ap.parse_args()

owner = a.repo.split("/")[0]
version = a.tag.lstrip("v")
base = f"https://github.com/{a.repo}"
now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

entry = {
    "version": version,
    "buildVersion": a.build,
    "date": now,
    "downloadURL": f"{base}/releases/download/{a.tag}/DoorUnlock-{a.tag}.ipa",
    "size": a.size,
    "minOSVersion": "15.0",
    "localizedDescription": a.notes or f"v{version}，详见 {base}/releases/tag/{a.tag}",
}

doc = {}
if os.path.exists(a.out):
    with open(a.out, encoding="utf-8") as f:
        doc = json.load(f)

apps = doc.get("apps") or [{}]
app = apps[0]
NEW_BUNDLE_ID = "io.github.kevin-2106.doorkey"
# 包名换过 (旧版是 com.selfuse.doorunlock)：旧包名的历史版本不能留在源里，否则会装出另一个 App
old = app.get("versions", []) if app.get("bundleIdentifier") == NEW_BUNDLE_ID else []
versions = [v for v in old if v.get("version") != version]
versions.insert(0, entry)

app.update({
    "name": "门钥",
    "bundleIdentifier": NEW_BUNDLE_ID,
    "developerName": owner,
    "subtitle": "住理生活门锁的非官方 iOS 客户端",
    "localizedDescription": "用你自己的账号换取你自己门锁的开门凭据，通过蓝牙 / NFC 开门；支持锁屏小组件、锁屏控制和 Action 按钮。与官方 App 及其厂商无关。",
    "iconURL": f"https://raw.githubusercontent.com/{a.repo}/main/docs/icon.png",
    "tintColor": "3478F6",
    "versions": versions,
    # 旧版 AltStore 源格式的单版本字段，兼容老客户端
    "version": entry["version"],
    "versionDate": entry["date"],
    "versionDescription": entry["localizedDescription"],
    "downloadURL": entry["downloadURL"],
    "size": entry["size"],
})

doc = {
    "name": "门钥",
    "identifier": f"io.github.{owner.lower()}.seu-dorm-unlock-ios",
    "subtitle": "SEU Dorm Unlock for iOS",
    "description": "门钥的 SideStore 源：添加后可以直接在 SideStore 里安装和更新。",
    "sourceURL": f"https://raw.githubusercontent.com/{a.repo}/source/apps.json",
    "apps": [app],
    "news": [],
}
with open(a.out, "w", encoding="utf-8") as f:
    json.dump(doc, f, ensure_ascii=False, indent=2)
    f.write("\n")
print(f"wrote {a.out}: {version} (build {a.build}), {len(versions)} version(s)")
