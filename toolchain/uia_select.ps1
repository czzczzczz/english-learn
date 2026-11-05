# 用 UI Automation 选中「Baidu TTS」列表项，触发右侧设置面板
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$proc = Get-Process STranslate
$root = [System.Windows.Automation.AutomationElement]::RootElement
$cond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $proc.Id)
$appWindows = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
Write-Host "windows: $($appWindows.Count)"

$target = $null
foreach ($w in $appWindows) {
    if ($w.Current.Name -eq "设置") { $target = $w; break }
}
if (-not $target) { Write-Host "settings window not found"; exit }

# 找名字含 Baidu TTS 的元素
$nameCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::NameProperty, "Baidu TTS")
$items = $target.FindAll([System.Windows.Automation.TreeScope]::Descendants, $nameCond)
Write-Host "matched elements: $($items.Count)"
foreach ($it in $items) {
    Write-Host ("  type=" + $it.Current.ControlType.ProgrammaticName + " name=" + $it.Current.Name)
}

if ($items.Count -gt 0) {
    $el = $items[0]
    try {
        $pattern = $el.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
        $pattern.Select()
        Write-Host "selected via SelectionItemPattern"
    } catch {
        try {
            $el.SetFocus()
            Write-Host "focused only: $($_.Exception.Message)"
        } catch { Write-Host "focus failed: $($_.Exception.Message)" }
    }
}
Start-Sleep -Milliseconds 800
