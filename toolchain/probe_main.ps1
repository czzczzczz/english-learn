$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

$p = Get-Process STranslate
$root = [System.Windows.Automation.AutomationElement]::RootElement
$cond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
$wins = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
Write-Output ("TOP WINDOWS: {0}" -f $wins.Count)
foreach ($w in $wins) {
    Write-Output ("  name='{0}' rect={1}" -f $w.Current.Name, $w.Current.BoundingRectangle)
}

$main = $null
foreach ($w in $wins) { if ($w.Current.Name -eq 'STranslate') { $main = $w } }
if ($null -eq $main) { Write-Output 'MAIN: NOT in UIA tree'; exit 0 }

$btnCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Button)
$btns = $main.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCond)
Write-Output ("MAIN BUTTONS: {0}" -f $btns.Count)
foreach ($b in $btns) {
    $rr = $b.Current.BoundingRectangle
    if ($b.Current.HelpText) {
        Write-Output ("  help='{0}' x={1:N0} y={2:N0}" -f $b.Current.HelpText, $rr.X, $rr.Y)
    }
}
