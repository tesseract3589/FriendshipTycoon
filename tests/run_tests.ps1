<#
Run from any directory. Each scene gets its own process and workspace-local logs.
Examples:
  ./tests/run_tests.ps1 -GodotPath 'C:\Godot\Godot_console.exe'
  ./tests/run_tests.ps1 -GodotPath 'C:\Godot\Godot_console.exe' -Scenes events,big_numbers
  ./tests/run_tests.ps1 -GodotPath 'C:\Godot\Godot_console.exe' -IncludeBalance
#>
param(
    [string]$GodotPath = $env:GODOT_BIN,
    [string[]]$Scenes = @(),
    [ValidateRange(1, 3600)][int]$TimeoutSeconds = 60,
    [ValidateRange(1, 3600)][int]$BalanceTimeoutSeconds = 300,
    [switch]$IncludeBalance
)

$ErrorActionPreference = 'Stop'

function Read-SharedLog([string]$Path) {
    # Redirected streams can still hold their handles briefly after a timeout kill.
    $stream = [IO.FileStream]::new($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $reader = [IO.StreamReader]::new($stream)
    try { return $reader.ReadToEnd() }
    finally { $reader.Dispose() }
}

$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $godotCommand = Get-Command godot -ErrorAction SilentlyContinue
    if ($null -eq $godotCommand) {
        throw 'Provide -GodotPath or set GODOT_BIN to the Godot console executable.'
    }
    $GodotPath = $godotCommand.Source
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot executable does not exist: $GodotPath"
}
if ($Scenes.Count -eq 0) {
    $Scenes = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.tscn' |
        Where-Object { $IncludeBalance -or $_.BaseName -ne 'balance_playthrough_v2' } |
        Sort-Object Name | ForEach-Object { $_.BaseName })
}
foreach ($scene in $Scenes) {
    if ($scene -notmatch '^[a-zA-Z0-9_]+$' -or
        -not (Test-Path -LiteralPath (Join-Path $PSScriptRoot ($scene + '.tscn')))) {
        throw "Unknown test scene: $scene"
    }
}
$runDirectory = Join-Path $projectRoot ('.godot/test_runs/' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
$results = @()
foreach ($scene in $Scenes) {
    $stdoutPath = Join-Path $runDirectory ($scene + '.stdout.log')
    $stderrPath = Join-Path $runDirectory ($scene + '.stderr.log')
    $engineLogPath = Join-Path $runDirectory ($scene + '.godot.log')
    $arguments = @('--headless', '--path', ('"' + $projectRoot + '"'),
        '--log-file', ('"' + $engineLogPath + '"'), '--max-fps', '120',
        ('res://tests/' + $scene + '.tscn'))
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $sceneTimeout = if ($scene -eq 'balance_playthrough_v2') { $BalanceTimeoutSeconds } else { $TimeoutSeconds }
    $process = Start-Process -FilePath $GodotPath -ArgumentList $arguments -WorkingDirectory $projectRoot `
        -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
    $timedOut = -not $process.WaitForExit($sceneTimeout * 1000)
    if ($timedOut) {
        $process.Kill($true)
    }
    $process.WaitForExit()
    $timer.Stop()
    $exitCode = $process.ExitCode
    $output = (Read-SharedLog $stdoutPath) + "`n" + (Read-SharedLog $stderrPath)
    $hasPass = $output -match '(?m)^PASS:'
    $diagnostics = @([regex]::Matches($output, '(?m)^(?:SCRIPT ERROR|ERROR|WARNING):[^\r\n]*') |
        ForEach-Object { $_.Value })
    $passed = -not $timedOut -and $exitCode -eq 0 -and $hasPass -and $diagnostics.Count -eq 0
    $reason = if ($timedOut) { "timeout after ${sceneTimeout}s" }
        elseif ($diagnostics.Count -gt 0) { $diagnostics -join ' | ' }
        elseif ($exitCode -ne 0) { "exit code $exitCode" }
        elseif (-not $hasPass) { 'no PASS marker' }
        else { '' }
    $result = [pscustomobject]@{
        Scene = $scene; Passed = $passed; ExitCode = $exitCode
        Seconds = [math]::Round($timer.Elapsed.TotalSeconds, 2); Reason = $reason
    }
    $results += $result
    $label = if ($passed) { 'PASS' } else { 'FAIL' }
    Write-Host ("{0} {1} ({2}s) {3}" -f $label, $scene, $result.Seconds, $reason)
    $process.Dispose()
}
$results | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $runDirectory 'results.json') -Encoding utf8
Write-Host ("Results: " + $runDirectory)
$failed = @($results | Where-Object { -not $_.Passed })
Write-Host ("{0}/{1} passed" -f ($results.Count - $failed.Count), $results.Count)
if ($failed.Count -gt 0) { exit 1 }
exit 0
