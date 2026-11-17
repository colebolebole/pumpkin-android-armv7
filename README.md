# Pumpkin for 32-bit Android (armv7, Android 5.0+)

Build scripts and a prebuilt binary of the [Pumpkin](https://github.com/Pumpkin-MC/Pumpkin) Minecraft server
for **32-bit ARM Android** (`armv7-linux-androideabi`), targeting **Android 5.0 (API 21) and newer**.

This is an unofficial build. It is not affiliated with the Pumpkin project. Pumpkin itself is unmodified;
the only addition is a small compatibility shim (see below).

## Download

Grab `pumpkin-armv7-android` from the [latest release](../../releases/latest) and verify it against `SHA256SUMS.txt`.

It is a plain command-line executable, not an APK. Run it over `adb`:

```bash
adb push pumpkin-armv7-android /data/local/tmp/pumpkin
adb shell chmod +x /data/local/tmp/pumpkin
adb shell "cd /data/local/tmp && ./pumpkin"
```

Pumpkin creates its config and world files in the working directory. Java Edition listens on port 25565 and
Bedrock on 19132.

**Status:** the binary builds and links cleanly and has the right ELF format and library dependencies
(`libc`, `libm`, `libdl` only). It has **not been tested on an Android device** yet. Please open an issue if
it crashes on yours, with the device model, Android version and output.

A 32-bit process can address at most about 2-4 GB of memory, and phones often have less free, so expect limits
with large worlds or many players.

## What is different from upstream

Android only added `getifaddrs`/`freeifaddrs` in API 24 (Android 7.0), and the `webrtc` crate Pumpkin uses for
Bedrock networking calls them. Without them, linking for API 21 fails with undefined symbols.
[`shim/ifaddrs_shim.c`](shim/ifaddrs_shim.c) provides both functions using `ioctl(SIOCGIFCONF)`, which works on
every Android version, and is linked into the final binary. Pumpkin's source is not changed.

Limitation: the shim reports **IPv4 interfaces only**. Java Edition is unaffected; IPv6 interfaces will not be
offered to Bedrock's WebRTC networking.

## Building it yourself

Requirements: Windows x64, `git`, Rust via [rustup](https://rustup.rs), about 10 GB of free disk and roughly
16 GB of RAM (the final crate peaks near 14 GB).

```powershell
./build.ps1
```

This will:

1. fetch Pumpkin at the pinned upstream commit,
2. download the Android NDK r27c (~745 MB) and verify its SHA-1 against Google's manifest,
3. add the Rust `armv7-linux-androideabi` target,
4. compile the shim,
5. build `pumpkin` and link the shim in,
6. write `dist/pumpkin-armv7-android` and `dist/SHA256SUMS.txt`.

A clean build takes roughly 20-30 minutes. Options: `-PumpkinCommit`, `-ApiLevel`, `-WorkDir`, `-PumpkinDir`, `-NdkDir`.

The script was developed and tested on Windows. For other hosts, the same recipe applies: point the target linker
(`CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER`) and `CC_`/`AR_` variables at the NDK's
`armv7a-linux-androideabi21-clang`, compile the shim with it, and build with
`cargo rustc --release --target armv7-linux-androideabi -p pumpkin --bin pumpkin -- -C link-arg=<path-to-shim.o>`.

## Source and license

Pumpkin is licensed under the GNU GPL v3, and so is this repository (see [LICENSE](LICENSE)).

The release binary was built from Pumpkin commit
[`87f8822ac36da62102350977be2f62f155a303dc`](https://github.com/Pumpkin-MC/Pumpkin/tree/87f8822ac36da62102350977be2f62f155a303dc)
(version 0.2.2+26.3-26.63) plus the shim in this repository. That commit and `shim/ifaddrs_shim.c` are the complete
corresponding source.
