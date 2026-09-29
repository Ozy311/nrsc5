<#
.SYNOPSIS
    Builds the NRSC-5 digital broadcast receiver library from source with
    MSYS2 (UCRT64) and installs it for the current user.

.DESCRIPTION
    Installs into %LOCALAPPDATA%\Programs\nrsc5 by default:
      bin\libnrsc5.dll (plus any MinGW runtime DLLs it needs)
      include\nrsc5.h
      lib\pkgconfig\nrsc5.pc

.PARAMETER Prefix
    Install prefix (default: %LOCALAPPDATA%\Programs\nrsc5, or $env:NRSC5_PREFIX).
.PARAMETER Yes
    Answer yes to prompts (unattended runs).
.PARAMETER NoDeps
    Do not update MSYS2 or install its build packages.
.PARAMETER OfflineDeps
    Build from local sources instead of downloading them. Expected layout:
    <dir>\faad2, <dir>\fftw-3.3.10.tar.gz, <dir>\libusb, <dir>\rtl-sdr.
.PARAMETER Msys2Root
    MSYS2 installation directory (default: $env:MSYS2_ROOT, or C:\msys64).
#>
[CmdletBinding()]
param(
    [string]$Prefix,
    [switch]$Yes,
    [switch]$NoDeps,
    [string]$OfflineDeps,
    [string]$Msys2Root
)
$ErrorActionPreference = 'Stop'

function Fail([string]$Message) {
    Write-Host "error: $Message" -ForegroundColor Red
    exit 1
}

function Invoke-Msys([string]$Command) {
    # Write-Host keeps the output on screen without becoming the function's return value.
    & $script:MsysShell -defterm -no-start -ucrt64 -here -c $Command | ForEach-Object { Write-Host $_ }
    return $LASTEXITCODE
}

try {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    if (-not $Prefix) { $Prefix = $env:NRSC5_PREFIX }
    if (-not $Prefix) { $Prefix = Join-Path $env:LOCALAPPDATA 'Programs\nrsc5' }
    $Prefix = [System.IO.Path]::GetFullPath($Prefix)
    if (-not $Msys2Root) { $Msys2Root = $env:MSYS2_ROOT }
    if (-not $Msys2Root) { $Msys2Root = 'C:\msys64' }
    $script:MsysShell = Join-Path $Msys2Root 'msys2_shell.cmd'

    if (-not (Test-Path -LiteralPath $script:MsysShell)) {
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Fail "MSYS2 was not found at $Msys2Root and winget is not available. Install MSYS2 from https://www.msys2.org and re-run."
        }
        if (-not $Yes) {
            $answer = Read-Host "MSYS2 was not found at $Msys2Root. Install it now with 'winget install -e --id MSYS2.MSYS2'? [y/N]"
            if ($answer -notmatch '^(y|yes)$') { Fail 'MSYS2 is required to build the library.' }
        }
        Write-Host '+ winget install -e --id MSYS2.MSYS2'
        & winget install -e --id MSYS2.MSYS2 --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) { Fail "winget could not install MSYS2 (exit code $LASTEXITCODE)." }
        if (-not (Test-Path -LiteralPath $script:MsysShell)) { Fail "MSYS2 was installed but $script:MsysShell does not exist; pass -Msys2Root." }
    }

    $resultFile = Join-Path $env:TEMP ("nrsc5-install-result-{0}.txt" -f $PID)
    Remove-Item -LiteralPath $resultFile -Force -ErrorAction SilentlyContinue
    $env:NRSC5_PREFIX = $Prefix
    $env:NRSC5_RESULT_FILE = $resultFile
    if ($NoDeps) { $env:NRSC5_NO_DEPS = '1' } else { Remove-Item Env:NRSC5_NO_DEPS -ErrorAction SilentlyContinue }
    if ($OfflineDeps) { $env:NRSC5_OFFLINE_DEPS = [System.IO.Path]::GetFullPath($OfflineDeps) } else { Remove-Item Env:NRSC5_OFFLINE_DEPS -ErrorAction SilentlyContinue }

    Push-Location $repoRoot
    try {
        if (-not $NoDeps) {
            # A first update can replace the MSYS2 runtime and end its shell early, so run it twice.
            Write-Host '==> Updating MSYS2'
            Write-Host '+ pacman -Syu --noconfirm'
            [void](Invoke-Msys 'pacman -Syu --noconfirm')
            [void](Invoke-Msys 'pacman -Syu --noconfirm')
        }
        Write-Host '==> Building inside the MSYS2 UCRT64 environment'
        $code = Invoke-Msys 'bash scripts/install-windows-msys2.sh'
    } finally {
        Pop-Location
    }

    if ($code -ne 0) { Fail "the MSYS2 build failed (exit code $code); see the output above." }
    if (-not (Test-Path -LiteralPath $resultFile)) { Fail 'the MSYS2 build ended without reporting success; see the output above.' }
    Remove-Item -LiteralPath $resultFile -Force -ErrorAction SilentlyContinue
    Write-Host "Installed to $Prefix"
} catch {
    Fail $_.Exception.Message
}
