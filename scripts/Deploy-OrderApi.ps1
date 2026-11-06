[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)][int]$Port = 8081,
    [Parameter(Mandatory)][string]$DeployDirectory
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$projectDirectory = Split-Path $PSScriptRoot -Parent
$artifacts = @(Get-ChildItem -LiteralPath (Join-Path $projectDirectory 'target') -Filter 'order-api-*.jar')
if ($artifacts.Count -ne 1) { throw 'Expected exactly one packaged Order API jar. Run Maven package first.' }

$deployPath = [IO.Path]::GetFullPath($DeployDirectory)
New-Item -ItemType Directory -Path $deployPath -Force | Out-Null
$jarPath = Join-Path $deployPath 'order-api.jar'
$pidPath = Join-Path $deployPath 'order-api.pid'
$oldProcess = $null
if (Test-Path -LiteralPath $pidPath) {
    $savedPid = [int](Get-Content -LiteralPath $pidPath -Raw).Trim()
    $oldProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $savedPid"
    if ($oldProcess -and ($oldProcess.Name -ne 'java.exe' -or
        !$oldProcess.CommandLine.Contains('"' + $jarPath + '"'))) {
        throw 'Saved PID belongs to a different process; refusing to stop it.'
    }
}
$listeners = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
foreach ($listener in $listeners) {
    if (!$oldProcess -or $listener.OwningProcess -ne $oldProcess.ProcessId) {
        throw "Port $Port is occupied by an unmanaged process. Choose another APP_PORT."
    }
}
if ($oldProcess) {
    Stop-Process -Id $oldProcess.ProcessId -Force -ErrorAction Stop
    Wait-Process -Id $oldProcess.ProcessId -Timeout 20 -ErrorAction SilentlyContinue
}
Copy-Item -LiteralPath $artifacts[0].FullName -Destination $jarPath -Force
$stdout = Join-Path $deployPath 'stdout.log'
$stderr = Join-Path $deployPath 'stderr.log'
$previousCookie = $env:JENKINS_NODE_COOKIE
$startedProcess = $null
try {
    # A distinct cookie keeps this deployment alive after Jenkins finishes the build.
    $env:JENKINS_NODE_COOKIE = 'order-api-deployment'
    $java = (Get-Command java.exe -ErrorAction Stop).Source
    $startedProcess = Start-Process -FilePath $java -ArgumentList @('-jar', ('"' + $jarPath + '"'), "--server.port=$Port") `
        -WorkingDirectory $deployPath -WindowStyle Hidden -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr -PassThru
    Set-Content -LiteralPath $pidPath -Value $startedProcess.Id

    $healthy = $false
    for ($attempt = 0; $attempt -lt 45; $attempt++) {
        $startedProcess.Refresh()
        if ($startedProcess.HasExited) { throw 'Order API exited during startup. See deployment logs.' }
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:$Port/api/orders" -UseBasicParsing -TimeoutSec 2
            $orders = @($response.Content | ConvertFrom-Json)
            if ($response.StatusCode -eq 200 -and $orders.Count -eq 1 -and
                $orders[0].id -eq 1 -and $orders[0].product -eq 'Laptop' -and
                $orders[0].quantity -eq 1 -and $orders[0].status -eq 'CREATED') {
                $healthy = $true
                break
            }
        } catch { Write-Verbose $_.Exception.Message }
        Start-Sleep -Seconds 2
    }
    if (!$healthy) { throw 'Order API failed its HTTP health check.' }
    Write-Output "Order API running: http://localhost:$Port/api/orders (PID $($startedProcess.Id))"
} catch {
    if ($startedProcess -and !$startedProcess.HasExited) {
        Stop-Process -Id $startedProcess.Id -Force -ErrorAction SilentlyContinue
    }
    throw
} finally {
    $env:JENKINS_NODE_COOKIE = $previousCookie
    if (Test-Path -LiteralPath $stdout) { Copy-Item -LiteralPath $stdout -Destination (Join-Path $projectDirectory 'target/deployment-stdout.log') -Force }
    if (Test-Path -LiteralPath $stderr) { Copy-Item -LiteralPath $stderr -Destination (Join-Path $projectDirectory 'target/deployment-stderr.log') -Force }
}
