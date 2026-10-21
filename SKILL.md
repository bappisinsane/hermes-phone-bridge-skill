---
name: hermes-phone-bridge-skill
description: Use when driving an Android phone or its Termux over USB.
---

# Hermes Phone Bridge Skill

## Overview

`adb shell` gives you the phone's **Android** shell as the `shell` user. It cannot see
Termux's `$PREFIX` (`/data/data/com.termux/files/usr`), and Termux's official external
bridge (`com.termux.permission.RUN_COMMAND`) is signature-protected so the shell user
cannot hold it. Those are two separate barriers — and the second has a working workaround.

Core principle: **get `adb` working first, then decide which shell you actually need.**
Most "I can't run commands on the phone" reports are simply a missing `adb` binary.

## When to Use

- Run commands on an Android device from the PC
- `adb` is not found, or the Android SDK exists without `platform-tools/`
- `adb devices` reports `unauthorized` or `offline`
- Run Termux packages (`node`, `python`, …) from the PC
- Push/pull files, install APKs, collect `logcat`

Not for: iOS devices, rooting, or wireless ADB setup.

## Step 1 — Get adb

`adb` ships in Google's `platform-tools`, **not** in the other Android SDK folders.

```bash
command -v adb || ls "$LOCALAPPDATA/Android/Sdk"
```

If the SDK exists but has no `platform-tools/`, download it — don't assume it's installed:

```bash
DEST="$HOME/Desktop/hermes-storage/android-platform-tools"; mkdir -p "$DEST"; cd "$DEST"
curl -sS -L --fail -o pt.zip https://dl.google.com/android/repository/platform-tools-latest-windows.zip
unzip -q -o pt.zip -d . && rm pt.zip
./platform-tools/adb.exe version
```

## Step 2 — Connect and authorize

```bash
ADB="$HOME/Desktop/hermes-storage/android-platform-tools/platform-tools/adb.exe"
"$ADB" devices -l
```

`unauthorized` is a **waiting RSA prompt**, not a broken cable. Fix in this order:

1. **Wake and unlock the phone screen.** Many OEM ROMs (realme/ColorOS, Xiaomi/MIUI) will not
   show the authorization dialog while the screen is off or locked.
2. **Developer options → Revoke USB debugging authorizations**, then unplug and replug the
   cable. The dialog reappears.
3. Tap **Allow** and tick **Always allow from this computer**.
4. Check the notification shade — some ROMs deliver the prompt as a heads-up notification.

Confirm before building anything on top:

```bash
"$ADB" devices -l     # must show "device", not "unauthorized" or "offline"
```

## Step 3 — Which shell do you actually need?

| You want | Use | Notes |
|---|---|---|
| Android shell (`getprop`, `pm`, `dumpsys`, `logcat`, `am`) | `adb shell …` | always works |
| Termux's Linux environment + packages | `run-as` bridge or Termux `sshd` | see below |

### Reaching Termux from the PC

`adb shell` runs as `shell` and cannot read or execute Termux's `$PREFIX`. Two ways in:

**Option A — Termux `sshd` (no build requirements).** In Termux: `pkg install openssh && sshd`
(listens on 8022). Then `ssh -p 8022 <termux-user>@<phone-ip>`. Over USB tethering the phone
is commonly `192.168.42.129` and the PC `192.168.42.x`.

**Option B — `run-as` on a debuggable Termux build.** The Termux *GitHub* release is built
with `android:debuggable=true`, so:

```bash
"$ADB" shell "run-as com.termux id"
# uid=10185(u0_a185) ... context=u:r:runas_app:s0   <- the Termux app, good
# uid=2000(shell)                                   <- wrong, see Step 4
```

Verify you genuinely have the app uid before building on it — a stale `uid=2000(shell)`
means the call silently degraded to the Android shell.

**The F-Droid Termux build is not debuggable**, so Option B breaks there. Pin the GitHub
debug build deliberately, or use Option A.

### Installing Termux over adb

```bash
"$ADB" install -r -d termux-app_<ver>+github-debug_arm64-v8a.apk
```

Match the APK to the device ABI (`ro.product.cpu.abi` → `arm64-v8a`, `armeabi-v7a`, …).
If `adb install` fails with `INSTALL_FAILED_VERIFICATION_FAILURE`, **just retry** — on
realme/ColorOS the first attempt commonly fails and the second succeeds.

## Step 4 — The quoting trap

`adb shell` joins its arguments with spaces before handing them to the device shell, so:

```bash
# WRONG - quotes consumed on the PC; the device shell sees them stripped and the whole
# thing silently runs as the Android `shell` user:
"$ADB" shell run-as com.termux files/usr/bin/bash -lc 'echo hi'

# RIGHT - the device command is ONE argument; the device shell parses the inner quotes:
"$ADB" shell "run-as com.termux files/usr/bin/bash -lc 'echo hi'"
```

Symptom of getting this wrong: `id` reports `uid=2000(shell)` and `$PREFIX` is empty, even
though the command "looks right".

**Don't fight this by hand — base64-carry the script:**

```bash
bash scripts/termux-run.sh my-script.sh
```

It exports `PREFIX`/`HOME`/`PATH`/`LD_LIBRARY_PATH` itself and pipes the decoded script into
Termux's bash. Copy it into the project rather than re-deriving the quoting each time.

## Pitfalls

- **`node` won't link after `pkg install nodejs`.** Termux's `nodejs` needs a current
  `openssl`; a stale one gives
  `CANNOT LINK EXECUTABLE "node": cannot locate symbol "OSSL_PROVIDER_add_conf_parameter"`.
  Run `pkg upgrade` (raises openssl) and retry — install `nodejs` *after* upgrading.
- **`pkg` mirror selection** prints `No mirror or mirror group selected` then picks one.
  Harmless, but it makes output noisy. Ignore it.
- **Termux's `$PREFIX` is not on the Android PATH.** Use absolute paths
  (`/data/data/com.termux/files/usr/bin/…`) or export `PATH` explicitly.
- **`run-as` only works on debuggable builds.** Verify with `adb shell "run-as com.termux id"`.
- **Don't `adb push` into `/data/data/<pkg>/`.** The `shell` user cannot write app-private
  storage. Push to `/sdcard/Download` or `/data/local/tmp`.
- **USB tethering is not shell access.** A phone showing `Remote NDIS based Internet Sharing
  Device` is reachable at the IP layer only — no shell, no ADB.
- **A device exposing only MTP + RNDIS has no ADB interface.** Check the USB interface list
  (`Get-PnpDevice`) before blaming the cable or driver.

## Quick reference

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

## Files

- `scripts/termux-run.sh` — run a local script inside Termux on the connected device.
