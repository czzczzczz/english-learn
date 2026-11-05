Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$proc = Get-Process STranslate
$root = [System.Windows.Automation.AutomationElement]::RootElement
$cond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $proc.Id)
$windows = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
$win = $null
foreach ($w in $windows) { if ($w.Current.ControlType -eq [System.Windows.Automation.ControlType]::Window) { $win = $w; break } }
if (-not $win) { Write-Host "no window"; exit }

$all = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants,
    [System.Windows.Automation.Condition]::TrueCondition)
Write-Host "descendants=$($all.Count)"
$i = 0
foreach ($el in $all) {
    $n = $el.Current.Name
    if ($n -and ($n.Contains("发音") -or $n.Contains("语速") -or $n.Contains("口音") -or $n.Contains("保存") -or $n.Contains("Token"))) {
        Write-Host ("  hit: " + $el.Current.ControlType.ProgrammaticName + " | " + $n)
    }
    $i++
}
Write-Host "scanned=$i"
