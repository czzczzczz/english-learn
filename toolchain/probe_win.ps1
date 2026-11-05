$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

$p = Get-Process STranslate
$root = [System.Windows.Automation.AutomationElement]::RootElement
$cond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
$main = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
Write-Output ("main rect = {0}" -f $main.Current.BoundingRectangle)

$btnCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Button)
$btns = $main.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCond)
foreach ($b in $btns) {
    $r = $b.Current.BoundingRectangle
    $help = $b.Current.HelpText
    Write-Output ("  btn x={0,5:N0} y={1,5:N0} w={2,4:N0} h={3,3:N0} name='{4}' help='{5}'" -f $r.X, $r.Y, $r.Width, $r.Height, $b.Current.Name, $help)
}
