param(
    [Parameter(Mandatory = $true)]
    [string] $Path,

    [string[]] $Include = @("*.exe", "*.dll")
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Path)) {
    throw "Path not found: $Path"
}

$item = Get-Item -LiteralPath $Path

if ($item.PSIsContainer) {
    $files = Get-ChildItem -LiteralPath $item.FullName -Recurse -File -Include $Include | Sort-Object FullName
} else {
    $files = @($item)
}

if (-not $files) {
    Write-Error "No files found to verify under: $Path"
}

$badSignatures = foreach ($file in $files) {
    $signature = Get-AuthenticodeSignature -FilePath $file.FullName
    if ($signature.Status -ne "Valid") {
        [PSCustomObject]@{
            Path = $file.FullName
            Status = $signature.Status
            StatusMessage = $signature.StatusMessage
        }
    }
}

if ($badSignatures) {
    Write-Host "Invalid Authenticode signatures:"
    $badSignatures | Format-Table -AutoSize | Out-String | Write-Host
    exit 1
}

Write-Host "Verified Authenticode signatures for $($files.Count) file(s)."
