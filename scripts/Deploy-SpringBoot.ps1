param(
    [Parameter(Mandatory = $true)][string]$DeployDirectory,
    [ValidateRange(1, 65535)][int]$Port = 8080
)
$ErrorActionPreference = 'Stop'

$artifacts = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '../target') -Filter '*.jar' -File)
if ($artifacts.Count -ne 1) { throw 'Expected exactly one packaged Spring Boot JAR.' }
$java = (Get-Command java.exe -ErrorAction Stop).Source
if (-not [IO.Path]::IsPathRooted($DeployDirectory)) { throw 'DEPLOY_DIR must be an absolute path.' }
$deployRoot = [IO.Path]::GetFullPath($DeployDirectory).TrimEnd('\')
$workspaceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
if ($deployRoot -eq $workspaceRoot -or $deployRoot.StartsWith($workspaceRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'DEPLOY_DIR must be outside the Jenkins workspace.'
}
New-Item -ItemType Directory -Path $deployRoot -Force | Out-Null
$jarPath = Join-Path $deployRoot 'order-api.jar'
$pidPath = Join-Path $deployRoot 'application.pid'
$stdoutPath = Join-Path $deployRoot 'application.stdout.log'
$stderrPath = Join-Path $deployRoot 'application.stderr.log'
$archivePath = Join-Path $workspaceRoot 'deployment-logs'
New-Item -ItemType Directory -Path $archivePath -Force | Out-Null

# Only stop a Java process whose command line identifies this deployment.
if (Test-Path -LiteralPath $pidPath) {
    $previousPid = [int](Get-Content -LiteralPath $pidPath -Raw).Trim()
    $previous = Get-CimInstance Win32_Process -Filter "ProcessId = $previousPid"
    if ($previous) {
        if ($previous.Name -ne 'java.exe' -or -not $previous.CommandLine.Contains('"' + $jarPath + '"')) {
            throw 'Saved PID does not identify this application; refusing to stop it.'
        }
        Stop-Process -Id $previousPid -ErrorAction Stop
        Wait-Process -Id $previousPid -Timeout 30 -ErrorAction SilentlyContinue
        if (Get-Process -Id $previousPid -ErrorAction SilentlyContinue) { throw 'Previous application did not stop.' }
    }
    Remove-Item -LiteralPath $pidPath
}

$app = $null
$launcher = $null
try {
    Copy-Item -LiteralPath $artifacts[0].FullName -Destination $jarPath -Force
    # Redirect all three streams in a separate hidden console. PowerShell's
    # asynchronous output redirection can keep the Jenkins step attached to Java.
    foreach ($path in @($java, $jarPath, $stdoutPath, $stderrPath)) {
        if ($path -match '[%"\r\n]') { throw 'Deployment paths must not contain percent signs, quotes or newlines.' }
    }
    $command = '""{0}" -jar "{1}" --server.port={2} <NUL >"{3}" 2>"{4}""' -f $java, $jarPath, $Port, $stdoutPath, $stderrPath
    $launcher = Start-Process -FilePath $env:ComSpec -ArgumentList @('/d', '/v:off', '/s', '/c', $command) `
        -WorkingDirectory $deployRoot -WindowStyle Hidden -PassThru
    $launchDeadline = (Get-Date).AddSeconds(10)
    do {
        $javaChild = Get-CimInstance Win32_Process -Filter "ParentProcessId = $($launcher.Id) AND Name = 'java.exe'" |
            Where-Object { $_.CommandLine.Contains('"' + $jarPath + '"') } | Select-Object -First 1
        if ($javaChild) { $app = Get-Process -Id $javaChild.ProcessId -ErrorAction Stop; break }
        $launcher.Refresh()
        if ($launcher.HasExited) { throw 'Java launcher exited before startup; check application logs.' }
        Start-Sleep -Milliseconds 200
    } while ((Get-Date) -lt $launchDeadline)
    if (-not $app) { throw 'Could not identify the launched Java process.' }
    Set-Content -LiteralPath $pidPath -Value $app.Id
    $deadline = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $deadline) {
        $app.Refresh()
        if ($app.HasExited) { throw "Spring Boot exited with code $($app.ExitCode)." }
        $healthy = $false
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:$Port/api/orders" -UseBasicParsing -TimeoutSec 3
            $healthy = $response.StatusCode -eq 200
        } catch { }
        # Verify this process owns the listening port, rather than accepting an old service.
        if ($healthy -and (Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue |
                Where-Object OwningProcess -eq $app.Id)) {
            Write-Host "Spring Boot started: PID $($app.Id), http://localhost:$Port/api/orders"
            return
        }
        Start-Sleep -Seconds 2
    }
    throw 'Spring Boot did not become ready within 90 seconds.'
} catch {
    if ($app -and -not $app.HasExited) { $app.Kill(); $app.WaitForExit() }
    if ($launcher -and -not $launcher.HasExited) { $launcher.Kill() }
    if (Test-Path -LiteralPath $pidPath) { Remove-Item -LiteralPath $pidPath }
    throw
} finally {
    foreach ($log in @($stdoutPath, $stderrPath)) {
        if (Test-Path -LiteralPath $log) {
            Get-Content -LiteralPath $log -Tail 200 | Set-Content -LiteralPath (Join-Path $archivePath ([IO.Path]::GetFileName($log)))
        }
    }
}
