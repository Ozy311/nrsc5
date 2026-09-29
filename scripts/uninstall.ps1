<#
.SYNOPSIS
    Removes exactly the files install-windows.ps1 installed, using the
    manifest written at install time (share\nrsc5\install-manifest.txt).

.PARAMETER Prefix
    Install prefix (default: %LOCALAPPDATA%\Programs\nrsc5, or $env:NRSC5_PREFIX).
#>
[CmdletBinding()]
param([string]$Prefix)
$ErrorActionPreference = 'Stop'

function Fail([string]$Message) {
    Write-Host "error: $Message" -ForegroundColor Red
    exit 1
}

try {
    if (-not $Prefix) { $Prefix = $env:NRSC5_PREFIX }
    if (-not $Prefix) { $Prefix = Join-Path $env:LOCALAPPDATA 'Programs\nrsc5' }
    $Prefix = [System.IO.Path]::GetFullPath($Prefix).TrimEnd('\')
    $manifest = Join-Path $Prefix 'share\nrsc5\install-manifest.txt'
    if (-not (Test-Path -LiteralPath $manifest)) { Fail "no install manifest at $manifest; nothing to uninstall" }

    $count = 0
    foreach ($line in (Get-Content -LiteralPath $manifest)) {
        if (-not $line.Trim()) { continue }
        $path = [System.IO.Path]::GetFullPath($line.Trim())
        if (-not $path.StartsWith($Prefix + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Host "skipping (outside $Prefix): $path"
            continue
        }
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force
            $count++
            Write-Host "removed $path"
        }
        $dir = Split-Path -Parent $path
        while ($dir.Length -gt $Prefix.Length -and (Test-Path -LiteralPath $dir) -and -not (Get-ChildItem -LiteralPath $dir -Force)) {
            Remove-Item -LiteralPath $dir -Force
            $dir = Split-Path -Parent $dir
        }
    }
    if ((Test-Path -LiteralPath $Prefix) -and -not (Get-ChildItem -LiteralPath $Prefix -Force)) {
        Remove-Item -LiteralPath $Prefix -Force
    }
    Write-Host "Uninstalled nrsc5 from $Prefix ($count files removed)"
} catch {
    Fail $_.Exception.Message
}
