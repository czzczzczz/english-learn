$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

$json = 'D:\vibe_coding\STranslate-dev\PortableConfig\Settings\Plugins\STranslate.Plugin.Tts.Baidu\3b128a5c578b4bce8c71bbff4e59c4a8.json'
$p = Get-Process STranslate
Write-Output ("PID: {0}  START: {1:HH:mm:ss}" -f $p.Id, $p.StartTime)

$root = [System.Windows.Automation.AutomationElement]::RootElement
$cond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
$win = $null
$wins = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
foreach ($w in $wins) { if ($w.Current.Name -eq '设置') { $win = $w } }
if ($null -eq $win) { Write-Output 'SETTINGS: missing'; exit 1 }

function Get-Combo($rootEl, $name) {
    $c = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::ComboBox)
    $all = $rootEl.FindAll([System.Windows.Automation.TreeScope]::Descendants, $c)
    foreach ($e in $all) { if ($e.Current.Name -eq $name) { return $e } }
    return $null
}

# 读取当前选中项（展开后看 ListItem IsSelected）
$liCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::ListItem)

foreach ($name in '单词发音源', '口音（单词）', '整句语速') {
    $combo = Get-Combo $win $name
    $combo.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand()
    Start-Sleep -Milliseconds 500
    $items = $combo.FindAll([System.Windows.Automation.TreeScope]::Descendants, $liCond)
    $picked = '(none)'
    foreach ($i in $items) {
        $sp = $i.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
        if ($sp.Current.IsSelected) { $picked = $i.Current.Name }
    }
    Write-Output ("{0} => {1}" -f $name, $picked)
    $combo.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Collapse()
    Start-Sleep -Milliseconds 250
}

Write-Output ("JSON  : " + ((Get-Content $json -Raw) -replace "`r?`n", ' '))

# 把口音切回美音（恢复默认演示值）
$accent = Get-Combo $win '口音（单词）'
$accent.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand()
Start-Sleep -Milliseconds 500
$items = $accent.FindAll([System.Windows.Automation.TreeScope]::Descendants, $liCond)
foreach ($i in $items) {
    if ($i.Current.Name -match '美音') {
        $i.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
        Write-Output 'RESTORE: 美音 US selected'
    }
}
Start-Sleep -Milliseconds 1000
Write-Output ("JSON2 : " + ((Get-Content $json -Raw) -replace "`r?`n", ' '))
