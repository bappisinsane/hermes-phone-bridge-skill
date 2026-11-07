<div align="center">

# Hermes Phone Bridge Skill

### Drive any Android phone's terminal over USB — including Termux's Linux environment, which `adb shell` can never reach.

[![Hermes Agent](https://img.shields.io/badge/Hermes%20Agent-skill-4a5568?style=for-the-badge)](#)
[![Android](https://img.shields.io/badge/Android-3DDC84?style=for-the-badge&logo=android&logoColor=white)](#)
[![Termux](https://img.shields.io/badge/Termux-0f111a?style=for-the-badge&logo=windows-terminal&logoColor=white)](#)
[![adb](https://img.shields.io/badge/adb-platform--tools-5f6368?style=for-the-badge)](#)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge)](#license)

**`adb shell` gives you the Android shell as the `shell` user.**
**This skill gives you the Linux shell — packages, Node, Python, the lot.**

[Quick start](#-quick-start) · [Why it exists](#-why-it-exists) · [How it works](#-how-it-works) · [Pitfalls](#-pitfalls) · [Reference](#-reference)

</div>

---

## Why it exists

`adb shell` runs as the `shell` user. It cannot read Termux's `$PREFIX`
(`/data/data/com.termux/files/usr`), and Termux's official external bridge
(`com.termux.permission.RUN_COMMAND`) is signature-protected so the `shell` user cannot
hold it either. Two barriers — and the second one has a working workaround.

Most *"I can't run commands on my phone"* reports are something simpler:

| Symptom | Usually is |
|---|---|
| `'adb' is not recognized` | The Android SDK exists, but `platform-tools/` is missing |
| `unauthorized` forever | A waiting RSA prompt the phone never showed you |
| Can't see Termux's packages | You're in the Android shell, not the Linux one |
| Quoting "randomly" breaks | `adb shell` joins its arguments with spaces |

This skill encodes the fixes for all four, plus the ones you only find by breaking them.

---

## Quick start

```bash
# 1. Get adb (it ships in platform-tools, not the rest of the SDK)
DEST="$HOME/Desktop/hermes-storage/android-platform-tools"; mkdir -p "$DEST"; cd "$DEST"
curl -sS -L --fail -o pt.zip \
  https://dl.google.com/android/repository/platform-tools-latest-windows.zip
unzip -q -o pt.zip -d . && rm pt.zip

# 2. Connect and authorize (wake + unlock the phone first)
export ADB="$DEST/platform-tools/adb.exe"
"$ADB" devices -l          # must print "device", not "unauthorized"

# 3. Run a script inside Termux — not inside Android
bash scripts/termux-run.sh probe.sh
```

### Real transcript

Actual output from a realme RMX3063 (Android 10, arm64-v8a, 1.8 GB RAM) with Termux
`v0.118.3+github-debug` installed:

```
$ bash scripts/termux-run.sh s1-probe.sh

model=RMX3063          android=10 (API 29)          abi=arm64-v8a
ram_total_kb=1813040

pkg search nodejs  ->  nodejs/stable,now 26.4.0-1 aarch64 [installed]
                       nodejs-lts/stable 24.18.0-1 aarch64

node -v            ->  v26.4.0
sqlite probe       ->  node:sqlite=PASS     sqlite_probe_exit=0
```

That is Termux's package manager and its Node runtime — reachable from the PC, over a
cable, with no terminal app open.

---

## How it works

### Step 1 — Get adb

`adb` ships in Google's `platform-tools`, **not** in the other Android SDK folders. If the
SDK is present but `platform-tools/` is absent, download it rather than assuming:

```bash
command -v adb || ls "$LOCALAPPDATA/Android/Sdk"
```

### Step 2 — Connect and authorize

```bash
"$ADB" devices -l
```

`unauthorized` is a **waiting RSA prompt**, not a broken cable. Fix in this order:

1. **Wake and unlock the phone screen.** Many OEM ROMs (realme/ColorOS, Xiaomi/MIUI) will not
   show the dialog while the screen is off or locked.
2. **Developer options → Revoke USB debugging authorizations**, then unplug and replug.
3. Tap **Allow** and tick **Always allow from this computer**.
4. Check the notification shade — some ROMs deliver the prompt as a heads-up.

Confirm before building anything on top: `adb devices -l` must show `device`, not
`unauthorized` or `offline`.

### Step 3 — Choose the shell you actually need

| You want | Use | Notes |
|---|---|---|
| Android shell (`getprop`, `pm`, `dumpsys`, `logcat`, `am`) | `adb shell …` | always works |
| Termux's Linux environment + packages | `run-as` bridge or Termux `sshd` | see below |

**Option A — Termux `sshd` (no build requirements).** In Termux: `pkg install openssh && sshd`
(listens on `8022`). Then `ssh -p 8022 <user>@<phone-ip>`. Over USB tethering the phone is
commonly `192.168.42.129`.

**Option B — `run-as` on a debuggable Termux build.** The Termux *GitHub* release is built
with `android:debuggable=true`:

```bash
"$ADB" shell "run-as com.termux id"
# uid=10185(u0_a185) ... context=u:r:runas_app:s0   <- the Termux app, good
# uid=2000(shell)                                   <- wrong, see Step 4
```

> **The F-Droid Termux build is not debuggable**, so Option B breaks there. Pin the GitHub
> debug build deliberately, or use Option A.

### Step 4 — The quoting trap

`adb shell` joins its arguments with spaces before handing them to the device shell:

```bash
# WRONG — quotes consumed on the PC; the device shell sees them stripped and the whole
# thing silently runs as the Android `shell` user:
"$ADB" shell run-as com.termux files/usr/bin/bash -lc 'echo hi'

# RIGHT — the device command is ONE argument; the device shell parses the inner quotes:
"$ADB" shell "run-as com.termux files/usr/bin/bash -lc 'echo hi'"
```

Symptom of getting this wrong: `id` reports `uid=2000(shell)` and `$PREFIX` is empty, even
though the command *looks* right.

**Don't fight this by hand — base64-carry the script.** `scripts/termux-run.sh` exports
`PREFIX`/`HOME`/`PATH`/`LD_LIBRARY_PATH` itself and pipes the decoded script into Termux's
bash. Copy it into the project rather than re-deriving the quoting each time.

---

## Pitfalls

Hard-won. Each one cost real time.

- **`node` won't link after `pkg install nodejs`.** Termux's `nodejs` needs a current
  `openssl`; a stale one gives
  `CANNOT LINK EXECUTABLE "node": cannot locate symbol "OSSL_PROVIDER_add_conf_parameter"`.
  Run `pkg upgrade` (raises openssl) and retry — install `nodejs` *after* upgrading.
- **`adb install` fails with `INSTALL_FAILED_VERIFICATION_FAILURE`.** On realme/ColorOS the
  first attempt commonly fails and the second succeeds. Just retry.
- **`pkg` prints `No mirror or mirror group selected`.** Harmless — it then picks one. Ignore
  the noise.
- **`$PREFIX` is not on the Android PATH.** Use absolute paths
  (`/data/data/com.termux/files/usr/bin/…`) or export `PATH` explicitly.
- **`run-as` only works on debuggable builds.** Verify with
  `adb shell "run-as com.termux id"` before relying on it.
- **Don't `adb push` into `/data/data/<pkg>/`.** The `shell` user cannot write app-private
  storage. Push to `/sdcard/Download` or `/data/local/tmp`.
- **USB tethering is not shell access.** A phone showing `Remote NDIS based Internet Sharing
  Device` is reachable at the IP layer only — no shell, no ADB.
- **A device exposing only MTP + RNDIS has no ADB interface.** Check the USB interface list
  before blaming the cable or driver.

---

## Reference

| Goal | Command |
|---|---|
| List devices | `adb devices -l` |
| Android shell | `adb shell getprop ro.product.model` |
| Device ABI | `adb shell getprop ro.product.cpu.abi` |
| RAM | `adb shell cat /proc/meminfo \| head -1` |
| Termux app-uid check | `adb shell "run-as com.termux id"` |
| Run a script inside Termux | `bash scripts/termux-run.sh script.sh` |
| Push a file | `adb push local /sdcard/Download/` |
| Install an APK | `adb install -r -d app.apk` |

---

## Install as a Hermes skill

Copy the skill into your Hermes skills directory:

```bash
mkdir -p "$LOCALAPPDATA/hermes/skills/android/hermes-phone-bridge-skill"
cp SKILL.md "$LOCALAPPDATA/hermes/skills/android/hermes-phone-bridge-skill/"
cp -r scripts "$LOCALAPPDATA/hermes/skills/android/hermes-phone-bridge-skill/"
```

It loads automatically when you ask for something it covers — a shell on an Android phone
over USB, a missing `adb`, an `unauthorized` device, or reaching Termux from the PC.

---

## Requirements

- **Host:** Windows / macOS / Linux with `bash`, `curl`, `unzip`, `base64`
- **Phone:** Android with Developer Options → USB debugging enabled
- **Termux:** the [GitHub debug build](https://github.com/termux/termux-app/releases) for
  the `run-as` bridge (Option B); the F-Droid build works with Termux `sshd` (Option A)
- **No root required**
- **Sync note:** this repo is the source of truth; the copy Hermes loads lives at
  `AppData\Local\hermes\skills\android\`. Keep them in sync after edits.

---

## License

MIT — see [LICENSE](LICENSE). Do what you like; a mention is nice but not required.

---

<div align="center">

*Built with a USB cable, a realme RMX3063, and three wasted attempts at quoting.*

</div>
