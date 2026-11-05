# 读取最近一次 .NET Runtime 崩溃的完整堆栈（含应用帧）
$events = Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=(Get-Date).AddMinutes(-60)} -ErrorAction SilentlyContinue |
    Where-Object { $_.ProviderName -match '.NET Runtime' } |
    Select-Object -First 1

if (-not $events) { Write-Output 'no crash event'; exit 0 }

$lines = $events.Message -split "`r?`n"
Write-Output ("--- " + $events.TimeCreated)
foreach ($l in $lines) {
    if ($l -match 'Exception Info|at System.Windows|at STranslate|at MS\.Internal|at System\.Xaml|at CommunityToolkit') {
        Write-Output $l
    }
}
