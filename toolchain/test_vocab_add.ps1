$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

$jsonPath = 'D:\vibe_coding\STranslate-dev\PortableConfig\Settings\Vocabulary.json'
Write-Output ("JSON EXISTS BEFORE: {0}" -f (Test-Path $jsonPath))

$p = Get-Process STranslate
$root = [System.Windows.Automation.AutomationElement]::RootElement
$cond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
$main = $null
$wins = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
foreach ($w in $wins) { if ($w.Current.Name -eq 'STranslate') { $main = $w } }
if ($null -eq $main) { Write-Output 'MAIN: missing'; exit 1 }

# 列出所有按钮的 HelpText，定位"加入生词本"
$btnCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Button)
$btns = $main.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCond)
Write-Output ("BUTTONS: {0}" -f $btns.Count)
$target = $null
foreach ($b in $btns) {
    $h = $b.Current.HelpText
    $n = $b.Current.Name
    if ($h -or $n) { Write-Output ("  help='{0}' name='{1}'" -f $h, $n) }
    if ($h -match '生词本') { $target = $b }
}
if ($null -eq $target) {
    Write-Output 'VOCAB BUTTON: not found'
} else {
    Write-Output 'VOCAB BUTTON: found'
}

# 输入框写入文本
$editCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Edit)
$edit = $main.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $editCond)
if ($edit) {
    $vp = $edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
    $vp.SetValue('hello')
    Write-Output 'INPUT: hello'
} else { Write-Output 'INPUT: edit not found'; exit 1 }
Start-Sleep -Milliseconds 800

if ($target) {
    $target.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    Write-Output 'VOCAB: invoked'
    Start-Sleep -Milliseconds 1500
}

Write-Output ("JSON EXISTS AFTER: {0}" -f (Test-Path $jsonPath))
if (Test-Path $jsonPath) { Write-Output (Get-Content $jsonPath -Raw) } else { Write-Output 'NO FILE' }
