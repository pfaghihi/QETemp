<#
Creates a Pipeline-from-SCM job and runs it with -CreateAndBuild.
Without that switch, retrieves the selected build's status and console log.
Requires a Jenkins username and user API token, prompted locally if omitted.
The agent must have the 'windows' label, Git, and Java 21 on PATH.
Required Jenkins plugins: Pipeline, Git, JUnit, and PowerShell pipeline steps.
For a private GitHub repo, supply an existing Jenkins Git credential ID.

Examples:
  .\scripts\Invoke-JenkinsPipeline.ps1 -CreateAndBuild
  .\scripts\Invoke-JenkinsPipeline.ps1 -BuildNumber 1
#>
[CmdletBinding()]
param(
    [uri]$JenkinsUrl = 'http://localhost:8088/',
    [ValidatePattern('^[A-Za-z0-9_-]+$')][string]$JobName = 'Order-API-CICD',
    [switch]$CreateAndBuild,
    [ValidatePattern('^(lastBuild|[1-9][0-9]*)$')][string]$BuildNumber = 'lastBuild',
    [string]$GitCredentialsId = '',
    [PSCredential]$Credential,
    [ValidateRange(1, 120)][int]$TimeoutMinutes = 20
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if ($JenkinsUrl.Scheme -ne 'https' -and !($JenkinsUrl.Scheme -eq 'http' -and $JenkinsUrl.IsLoopback)) {
    throw 'Use HTTPS for remote Jenkins credentials; HTTP is supported only on loopback.'
}
if (!$Credential) { $Credential = Get-Credential -Message 'Jenkins username; enter your Jenkins API token as the password' }
$encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(
    $Credential.UserName + ':' + $Credential.GetNetworkCredential().Password))
$headers = @{ Authorization = "Basic $encoded" }
$baseUrl = $JenkinsUrl.AbsoluteUri.TrimEnd('/')
$jobUrl = "$baseUrl/job/$JobName"
$outputDirectory = Join-Path (Split-Path $PSScriptRoot -Parent) 'target/jenkins'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

function Get-JenkinsJson([string]$Url) {
    Invoke-RestMethod -Uri $Url -Headers $headers -Method Get -TimeoutSec 30
}

try {
    $identity = Get-JenkinsJson "$baseUrl/whoAmI/api/json"
    if (!$identity.authenticated) { throw 'Jenkins did not authenticate the supplied username and API token.' }

    # Validate the actual Jenkinsfile against this controller before creating a job.
    if ($CreateAndBuild) {
        $jenkinsfile = Get-Content -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'Jenkinsfile') -Raw
        $validation = Invoke-RestMethod -Uri "$baseUrl/pipeline-model-converter/validate" -Headers $headers `
            -Method Post -Body @{ jenkinsfile = $jenkinsfile } -TimeoutSec 30
        if ([string]$validation -notmatch 'Jenkinsfile successfully validated') {
            throw "Jenkinsfile validation failed: $validation"
        }
        Write-Output 'Jenkinsfile validated by Jenkins.'

        $exists = $true
        try { $null = Get-JenkinsJson "$jobUrl/api/json" } catch {
            if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) { $exists = $false } else { throw }
        }
        if (!$exists) {
            $escapedCredentials = [Security.SecurityElement]::Escape($GitCredentialsId)
            $jobXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<flow-definition plugin="workflow-job">
  <description>Order API: GitHub checkout, Maven compile/test/package, Windows deployment, JUnit reports.</description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition" plugin="workflow-cps">
    <scm class="hudson.plugins.git.GitSCM" plugin="git">
      <configVersion>2</configVersion>
      <userRemoteConfigs><hudson.plugins.git.UserRemoteConfig>
        <url>https://github.com/pfaghihi/QETemp.git</url>
        <credentialsId>$escapedCredentials</credentialsId>
      </hudson.plugins.git.UserRemoteConfig></userRemoteConfigs>
      <branches><hudson.plugins.git.BranchSpec><name>*/main</name></hudson.plugins.git.BranchSpec></branches>
      <doGenerateSubmoduleConfigurations>false</doGenerateSubmoduleConfigurations>
      <submoduleCfg class="empty-list"/><extensions/>
    </scm>
    <scriptPath>Jenkinsfile</scriptPath><lightweight>true</lightweight>
  </definition>
  <triggers/><disabled>false</disabled>
</flow-definition>
"@
            $null = Invoke-WebRequest -Uri "$baseUrl/createItem?name=$JobName" -Method Post -Headers $headers `
                -ContentType 'application/xml' -Body ([Text.Encoding]::UTF8.GetBytes($jobXml)) -UseBasicParsing -TimeoutSec 30
        } else {
            [xml]$existing = (Invoke-WebRequest -Uri "$jobUrl/config.xml" -Headers $headers -UseBasicParsing -TimeoutSec 30).Content
            if ($existing.'flow-definition'.definition.scm.userRemoteConfigs.'hudson.plugins.git.UserRemoteConfig'.url -ne 'https://github.com/pfaghihi/QETemp.git' -or
                $existing.'flow-definition'.definition.scriptPath -ne 'Jenkinsfile') {
                throw 'An unrelated job already uses this name. Choose another JobName.'
            }
        }

        $jobDetails = Get-JenkinsJson "$jobUrl/api/json"
        $buildAction = if (@($jobDetails.property | Where-Object { $_.parameterDefinitions }).Count) { 'buildWithParameters' } else { 'build' }
        $queued = Invoke-WebRequest -Uri "$jobUrl/$buildAction" -Method Post -Headers $headers -UseBasicParsing -TimeoutSec 30
        $queueUrl = [uri]::new($JenkinsUrl, [string]$queued.Headers['Location'])
        if ($queueUrl.Authority -ne $JenkinsUrl.Authority -or $queueUrl.Scheme -ne $JenkinsUrl.Scheme -or $queueUrl.AbsolutePath -notmatch '/queue/item/[0-9]+/') {
            throw 'Unexpected Jenkins queue URL; check the Jenkins root URL configuration.'
        }
        $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
        do {
            $queue = Get-JenkinsJson ($queueUrl.AbsoluteUri.TrimEnd('/') + '/api/json')
            if ($queue.cancelled) { throw 'The queued build was cancelled.' }
            if ($queue.executable) { $BuildNumber = [string]$queue.executable.number; break }
            Write-Output "Queued: $($queue.why)"
            if ((Get-Date) -gt $deadline) { throw "Queue wait timed out. Check $jobUrl" }
            Start-Sleep -Seconds 5
        } while ($true)
    }

    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    do {
        $build = Get-JenkinsJson "$jobUrl/$BuildNumber/api/json"
        # Resolve lastBuild once, so a newer build cannot change the monitored run.
        $BuildNumber = [string]$build.number
        $build | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $outputDirectory "build-$BuildNumber.json") -Encoding UTF8
        Invoke-WebRequest -Uri "$jobUrl/$BuildNumber/consoleText" -Headers $headers -UseBasicParsing -TimeoutSec 30 `
            -OutFile (Join-Path $outputDirectory "build-$BuildNumber.log")
        Write-Output "Build #$BuildNumber : building=$($build.building), result=$($build.result)"
        if (!$build.building) { break }
        if ((Get-Date) -gt $deadline) { throw 'Build wait timed out; latest status and console log have been saved.' }
        Start-Sleep -Seconds 5
    } while ($true)
    Write-Output "Console: $jobUrl/$BuildNumber/console"
    Write-Output "JUnit: $jobUrl/$BuildNumber/testReport/"
    Write-Output "Downloaded status and logs: $outputDirectory"
    if ($build.result -ne 'SUCCESS') { throw "Jenkins build completed with result $($build.result). See downloaded log." }
} finally {
    $headers.Clear()
    $encoded = $null
    $Credential = $null
}
