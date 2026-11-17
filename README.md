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

Requirements: Windows x64, `git`, Rust via [rustup](https://rustup.rs), about 10 GB of free disk and 12 GB or more of
RAM (peak is about 8 GB for the compiler, plus the OS).

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

A clean build takes roughly 20-30 minutes. Options: `-PumpkinCommit`, `-ApiLevel`, `-WorkDir`, `-PumpkinDir`,
`-NdkDir`, and the build-profile options `-Lto` (`thin` by default; `fat` or `default` is Pumpkin's own profile),
`-Strip` (`symbols` by default) and `-Jobs`. For example, `./build.ps1 -Lto default -Strip default` builds with
Pumpkin's own release profile, which needs much more time. The v0.2.2 release was built that way.

The script was developed and tested on Windows. For other hosts, the same recipe applies: point the target linker
(`CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER`) and `CC_`/`AR_` variables at the NDK's
`armv7a-linux-androideabi21-clang`, compile the shim with it, and build with
`cargo rustc --release --target armv7-linux-androideabi -p pumpkin --bin pumpkin -- -C link-arg=<path-to-shim.o>`.

## Building with GitHub Actions

The workflow in [`.github/workflows/build.yml`](.github/workflows/build.yml) runs `build.ps1` on a GitHub-hosted
Windows runner. You can use it from your own fork:

- **Build only:** go to *Actions → Build Android armv7 → Run workflow*. The binary and its checksum are attached to
  the run as the `pumpkin-armv7-android` artifact (kept for 30 days).
- **Build and publish a release:** enter a `release_tag` such as `v0.2.3` when running the workflow, or push a tag
  that starts with `v`. The binary and `SHA256SUMS.txt` are attached to a GitHub release for that tag.
- **Different Pumpkin version:** set `pumpkin_commit` to a full 40-character upstream commit hash. The default is the
  commit pinned in `build.ps1`.

CI builds use thin LTO, stripped symbols and 2 parallel jobs by default. The workflow has inputs to change each of
them, and every run reports its build time, peak memory and binary size in the run summary.

Measured on a standard GitHub Windows runner (4 CPUs, 16 GB RAM):

| LTO | Other settings | Build time | Peak memory (all compiler processes) | Binary |
|---|---|---|---|---|
| fat (Pumpkin's own profile) | debuginfo stripped | 57 min | 9.5 GB | 87 MB |
| thin | debuginfo stripped | 24 min | 9.0 GB | 118 MB |
| thin | symbols stripped (default here) | 18 min | 8.5 GB | 78 MB |
| thin | debuginfo stripped, 2 jobs | 25 min | 8.0 GB | 118 MB |
| thin | debuginfo stripped, 1 job | 50 min | 7.9 GB | 118 MB |
| off | debuginfo stripped | 14 min | 8.4 GB | 131 MB |

Memory has a floor of about 8 GB: compiling the `pumpkin-data` crate alone takes about 7.8 GB in a single rustc
process, whatever the LTO setting, job count, optimization level or codegen-unit count. LTO mostly affects build time
and binary size. Thin LTO should run slightly slower than fat LTO at runtime; I haven't measured it. Stripped symbols
mean panic backtraces show no function names; use `strip: debuginfo` for a debuggable build.

### Automatic update check

[`.github/workflows/check-upstream.yml`](.github/workflows/check-upstream.yml) runs daily and looks at the latest
stable (non-prerelease) Pumpkin release. If it is newer than our latest release and not built yet, it starts a
build-only run and opens an issue containing the command to publish it. Releases made from upstream releases are
tagged `v<upstream tag>`, for example `v0.2.3+26.3-26.65`.

By default nothing is published without you. To publish automatically after a successful build, set `AUTO_PUBLISH`
to `'true'` at the top of that workflow. GitHub pauses scheduled workflows in repositories with no activity for 60
days; re-enable it from the Actions tab if that happens.

## Source and license

Pumpkin is licensed under the GNU GPL v3, and so is this repository (see [LICENSE](LICENSE)).

The release binary was built from Pumpkin commit
[`87f8822ac36da62102350977be2f62f155a303dc`](https://github.com/Pumpkin-MC/Pumpkin/tree/87f8822ac36da62102350977be2f62f155a303dc)
(version 0.2.2+26.3-26.63) plus the shim in this repository. That commit and `shim/ifaddrs_shim.c` are the complete
corresponding source.
