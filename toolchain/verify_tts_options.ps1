$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

$json = 'D:\vibe_coding\STranslate-dev\PortableConfig\Settings\Plugins\STranslate.Plugin.Tts.Baidu\3b128a5c578b4bce8c71bbff4e59c4a8.json'
Write-Output ("BEFORE: " + (Get-Content $json -Raw))

$p = Get-Process STranslate
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

$accent = Get-Combo $win '口音（单词）'
if ($null -eq $accent) { Write-Output 'ACCENT: combobox missing'; exit 1 }
$accent.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand()
Start-Sleep -Milliseconds 800

# 在展开的下拉里按 ListItem 类型找「英音 UK」
$liCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::ListItem)
$items = $accent.FindAll([System.Windows.Automation.TreeScope]::Descendants, $liCond)
Write-Output ("LISTITEMS: {0}" -f $items.Count)
$target = $null
foreach ($i in $items) {
    Write-Output ("  item: '{0}'" -f $i.Current.Name)
    if ($i.Current.Name -match '英音') { $target = $i }
}
if ($null -eq $target) {
    $all = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $liCond)
    Write-Output ("FALLBACK LISTITEMS: {0}" -f $all.Count)
    foreach ($i in $all) {
        if ($i.Current.Name -match '英音') { $target = $i }
    }
}
if ($target) {
    $target.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
    Write-Output 'ACCENT: 英音 UK selected'
} else { Write-Output 'ACCENT: item not found' }
Start-Sleep -Milliseconds 1200

Write-Output ("AFTER : " + (Get-Content $json -Raw))

$btnCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::NameProperty, '试听单词')
$btn = $win.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $btnCond)
if ($btn) {
    $btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    Write-Output 'PREVIEW: invoked'
} else { Write-Output 'PREVIEW: button missing' }
Start-Sleep -Milliseconds 3500

$texts = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants,
    [System.Windows.Automation.Condition]::TrueCondition)
$err = @()
foreach ($e in $texts) {
    if ($e.Current.ControlType -eq [System.Windows.Automation.ControlType]::Text -and
        $e.Current.Name -match '失败|未找到') { $err += $e.Current.Name }
}
Write-Output ("ERROR TEXTS: " + ($(if ($err.Count) { $err -join ' | ' } else { 'none' })))
