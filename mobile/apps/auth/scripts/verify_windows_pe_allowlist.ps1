param(
    [Parameter(Mandatory = $true)]
    [string] $PayloadDir,

    [Parameter(Mandatory = $true)]
    [string] $AllowlistPath
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $PayloadDir -PathType Container)) {
    throw "Payload directory not found: $PayloadDir"
}

if (-not (Test-Path -LiteralPath $AllowlistPath -PathType Leaf)) {
    throw "Allowlist not found: $AllowlistPath"
}

$payloadRoot = (Resolve-Path -LiteralPath $PayloadDir).Path
$allowlist = Get-Content -LiteralPath $AllowlistPath |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith("#") } |
    ForEach-Object { $_.Replace("\", "/") }

$duplicateEntries = $allowlist |
    Group-Object |
    Where-Object { $_.Count -gt 1 } |
    ForEach-Object { $_.Name }

if ($duplicateEntries) {
    Write-Host "Duplicate entries in ${AllowlistPath}:"
    $duplicateEntries | ForEach-Object { Write-Host "  $_" }
    exit 1
}

$allowed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($entry in $allowlist) {
    [void] $allowed.Add($entry)
}

$payloadFiles = Get-ChildItem -LiteralPath $payloadRoot -Recurse -File -Include *.exe, *.dll |
    ForEach-Object {
        [PSCustomObject]@{
            File = $_
            RelativePath = [System.IO.Path]::GetRelativePath($payloadRoot, $_.FullName).Replace("\", "/")
        }
    } |
    Sort-Object RelativePath

if (-not $payloadFiles) {
    Write-Error "No Windows PE files found in payload directory: $payloadRoot"
}

$actual = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($file in $payloadFiles) {
    [void] $actual.Add($file.RelativePath)
}

$unexpected = $payloadFiles |
    Where-Object { -not $allowed.Contains($_.RelativePath) } |
    ForEach-Object { $_.RelativePath }

$missing = $allowlist |
    Where-Object { -not $actual.Contains($_) } |
    Sort-Object

Write-Host "Windows PE files found in payload:"
$payloadFiles | ForEach-Object { Write-Host "  $($_.RelativePath)" }

if ($unexpected -or $missing) {
    if ($unexpected) {
        Write-Host "Unexpected Windows PE files. Review each file before adding it to ${AllowlistPath}:"
        $unexpected | ForEach-Object { Write-Host "  $_" }
    }

    if ($missing) {
        Write-Host "Allowlisted Windows PE files missing from payload. Remove only after confirming the binary is no longer shipped:"
        $missing | ForEach-Object { Write-Host "  $_" }
    }

    exit 1
}

Write-Host "Windows PE allowlist matched $($payloadFiles.Count) file(s)."
