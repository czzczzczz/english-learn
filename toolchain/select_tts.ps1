# 在设置窗口里切到「语音合成」并选中 Baidu TTS，触发插件设置面板
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

$proc = Get-Process STranslate
$root = [System.Windows.Automation.AutomationElement]::RootElement
$cond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $proc.Id)
$windows = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
Write-Host "windows=$($windows.Count)"

$win = $null
foreach ($w in $windows) {
    if ($w.Current.ControlType -eq [System.Windows.Automation.ControlType]::Window) { $win = $w; break }
}
if (-not $win) { Write-Host "no window"; exit }

# 左侧导航：语音合成
$nameCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::NameProperty, "语音合成")
$nav = $win.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $nameCond)
if ($nav) {
    $nav.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
    Write-Host "nav selected"
} else { Write-Host "nav not found" }
Start-Sleep -Milliseconds 1000

# 服务项
$svcCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::NameProperty, "Baidu TTS")
$item = $win.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $svcCond)
if ($item) {
    $item.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
    Write-Host "service selected"
} else { Write-Host "service not found" }
Start-Sleep -Milliseconds 1200
