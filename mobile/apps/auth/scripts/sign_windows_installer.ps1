param(
    [Parameter(Mandatory = $true)]
    [string] $Path
)

$ErrorActionPreference = "Stop"

# The payload signing action installs this module before Inno Setup runs.
Import-Module ArtifactSigning

$signingParameters = @{
    Endpoint = $env:AZURE_ENDPOINT
    CodeSigningAccountName = $env:AZURE_CODE_SIGNING_NAME
    CertificateProfileName = $env:AZURE_CERT_PROFILE_NAME
    Files = $Path
    FileDigest = "SHA256"
    TimestampRfc3161 = "http://timestamp.acs.microsoft.com"
    TimestampDigest = "SHA256"
    ExcludeWorkloadIdentityCredential = $true
    ExcludeManagedIdentityCredential = $true
    ExcludeSharedTokenCacheCredential = $true
    ExcludeVisualStudioCredential = $true
    ExcludeVisualStudioCodeCredential = $true
    ExcludeAzurePowerShellCredential = $true
    ExcludeAzureDeveloperCliCredential = $true
    ExcludeInteractiveBrowserCredential = $true
}
Invoke-ArtifactSigning @signingParameters
& "$PSScriptRoot/verify_windows_authenticode.ps1" -Path $Path
if (-not $?) {
    exit 1
}
