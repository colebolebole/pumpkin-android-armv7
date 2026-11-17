<#
.SYNOPSIS
  Builds the Pumpkin Minecraft server for 32-bit ARM Android (armv7-linux-androideabi, Android 5.0 / API 21+).

.DESCRIPTION
  1. Fetches Pumpkin at a pinned upstream commit (skipped if -PumpkinDir already exists).
  2. Downloads the Android NDK from Google and verifies its SHA-1 (skipped if -NdkDir already exists).
  3. Adds the armv7-linux-androideabi Rust target.
  4. Compiles shim/ifaddrs_shim.c (getifaddrs/freeifaddrs for API < 24).
  5. Builds the `pumpkin` binary and links the shim into it.
  6. Copies the result to dist/ and writes a SHA-256 checksum.

  Requirements: Windows x64, git, Rust via rustup (https://rustup.rs), ~10 GB free disk and
  roughly 16 GB RAM (the final crate peaks near 14 GB). Expect 20-30 minutes on a clean build.
#>
param(
    [string]$WorkDir       = (Join-Path $PSScriptRoot 'work'),
    [string]$PumpkinDir    = (Join-Path $WorkDir 'Pumpkin'),
    [string]$NdkDir        = (Join-Path $WorkDir 'android-ndk'),
    [string]$PumpkinCommit = '87f8822ac36da62102350977be2f62f155a303dc',
    [int]$ApiLevel         = 21
)

# Native tools (rustup, cargo, git) write progress to stderr, which Windows PowerShell 5.1 would treat
# as an error under 'Stop'. Failures are caught through exit codes (Assert-Ok) and -ErrorAction Stop instead.
$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

$Target     = 'armv7-linux-androideabi'
$NdkVersion = 'r27c'
$NdkUrl     = "https://dl.google.com/android/repository/android-ndk-$NdkVersion-windows.zip"
$NdkSha1    = 'ac5f7762764b1f15341094e148ad4f847d050c38'   # from https://dl.google.com/android/repository/repository2-3.xml
$DistDir    = Join-Path $PSScriptRoot 'dist'

function Assert-Ok($what) {
    if ($LASTEXITCODE -ne 0) { throw "$what failed (exit code $LASTEXITCODE)" }
}

foreach ($tool in 'git', 'cargo', 'rustup') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "'$tool' was not found on PATH. Install git and Rust (https://rustup.rs) first."
    }
}

New-Item -ItemType Directory -Force $WorkDir, $DistDir -ErrorAction Stop | Out-Null

# --- 1. Pumpkin source ------------------------------------------------------
if (-not (Test-Path (Join-Path $PumpkinDir '.git'))) {
    Write-Host "Fetching Pumpkin $PumpkinCommit ..."
    New-Item -ItemType Directory -Force $PumpkinDir -ErrorAction Stop | Out-Null
    git -C $PumpkinDir init -q;                                                   Assert-Ok 'git init'
    git -C $PumpkinDir remote add origin https://github.com/Pumpkin-MC/Pumpkin.git; Assert-Ok 'git remote add'
    git -C $PumpkinDir fetch --depth 1 origin $PumpkinCommit;                     Assert-Ok 'git fetch'
    git -C $PumpkinDir checkout -q FETCH_HEAD;                                    Assert-Ok 'git checkout'
}
$head = (git -C $PumpkinDir rev-parse HEAD).Trim()
if ($head -ne $PumpkinCommit) {
    Write-Warning "Pumpkin checkout is at $head, not the pinned $PumpkinCommit. Building it anyway."
}

# --- 2. Android NDK ---------------------------------------------------------
$ndkRoot = Join-Path $NdkDir "android-ndk-$NdkVersion"
if (-not (Test-Path $ndkRoot)) {
    $zip = Join-Path $WorkDir "android-ndk-$NdkVersion-windows.zip"
    Write-Host "Downloading Android NDK $NdkVersion (~745 MB) ..."
    curl.exe -L -C - --fail -sS -o $zip $NdkUrl; Assert-Ok 'NDK download'
    $actual = (Get-FileHash $zip -Algorithm SHA1 -ErrorAction Stop).Hash.ToLower()
    if ($actual -ne $NdkSha1) { throw "NDK checksum mismatch: expected $NdkSha1, got $actual" }
    Write-Host 'Extracting NDK ...'
    Expand-Archive $zip -DestinationPath $NdkDir -Force -ErrorAction Stop
}
$bin = Join-Path $ndkRoot 'toolchains\llvm\prebuilt\windows-x86_64\bin'
$clang   = Join-Path $bin "armv7a-linux-androideabi$ApiLevel-clang.cmd"
$clangxx = Join-Path $bin "armv7a-linux-androideabi$ApiLevel-clang++.cmd"
if (-not (Test-Path $clang)) { throw "NDK has no clang wrapper for API $ApiLevel : $clang" }

# --- 3. Rust target ---------------------------------------------------------
rustup target add $Target; Assert-Ok 'rustup target add'

# --- 4. Compile the getifaddrs shim ----------------------------------------
$shimObj = Join-Path $WorkDir 'ifaddrs_shim.o'
& $clang -c -O2 -fPIC -Wall -o $shimObj (Join-Path $PSScriptRoot 'shim\ifaddrs_shim.c'); Assert-Ok 'shim compile'

# --- 5. Build ---------------------------------------------------------------
$env:CC_armv7_linux_androideabi  = $clang
$env:CXX_armv7_linux_androideabi = $clangxx
$env:AR_armv7_linux_androideabi  = Join-Path $bin 'llvm-ar.exe'
$env:CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER = $clang

Push-Location $PumpkinDir
try {
    cargo rustc --release --target $Target -p pumpkin --bin pumpkin -- -C "link-arg=$shimObj"
    Assert-Ok 'cargo build'
} finally {
    Pop-Location
}

# --- 6. Collect output ------------------------------------------------------
$built = Join-Path $PumpkinDir "target\$Target\release\pumpkin"
$out   = Join-Path $DistDir 'pumpkin-armv7-android'
Copy-Item $built $out -Force -ErrorAction Stop
$sha = (Get-FileHash $out -Algorithm SHA256 -ErrorAction Stop).Hash.ToLower()
"$sha  pumpkin-armv7-android" | Set-Content -Encoding ascii (Join-Path $DistDir 'SHA256SUMS.txt')

Write-Host ''
Write-Host "Built: $out"
Write-Host "SHA-256: $sha"
