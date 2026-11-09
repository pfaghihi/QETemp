param(
    [Parameter(Mandatory = $true)][uri]$BuildUrl,
    [string]$OutputDirectory = 'jenkins-build-output'
)
$ErrorActionPreference = 'Stop'
if ($BuildUrl.Scheme -notin @('http', 'https')) { throw 'Provide an HTTP or HTTPS Jenkins build URL.' }
if (-not $env:JENKINS_USER -or -not $env:JENKINS_API_TOKEN) {
    throw 'Set JENKINS_USER and JENKINS_API_TOKEN environment variables first.'
}
$encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($env:JENKINS_USER):$($env:JENKINS_API_TOKEN)"))
$headers = @{ Authorization = "Basic $encoded" }
$baseUrl = $BuildUrl.AbsoluteUri.TrimEnd('/')
$status = Invoke-RestMethod -Uri ($baseUrl + '/api/json?tree=number,result,building,url,duration') -Headers $headers -MaximumRedirection 0 -TimeoutSec 30
# Resolve lastBuild to the returned build number so logs belong to the same build.
$baseUrl = $baseUrl.Substring(0, $baseUrl.LastIndexOf('/')) + '/' + $status.number
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$status | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDirectory 'status.json')
Invoke-WebRequest -Uri ($baseUrl + '/consoleText') -Headers $headers -UseBasicParsing -MaximumRedirection 0 -TimeoutSec 30 `
    -OutFile (Join-Path $OutputDirectory 'console.log')
$status | Select-Object number, result, building, duration, url
Write-Host "Status and console log saved to $OutputDirectory"
