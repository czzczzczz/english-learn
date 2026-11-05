$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class K17 {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  public static IntPtr Find(uint pid, string title){
    IntPtr f = IntPtr.Zero;
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid){ var sb=new StringBuilder(512); GetWindowText(h,sb,512); if(sb.ToString()==title){ f=h; return false; } } return true; }, IntPtr.Zero);
    return f;
  }
}
"@

$json = 'D:\vibe_coding\STranslate-dev\PortableConfig\Settings\Vocabulary.json'
Write-Output ("BEFORE: " + ((Get-Content $json -Raw) -replace "`r?`n", ' ').Substring(0, [Math]::Min(220, (Get-Content $json -Raw).Length)))

$p = Get-Process STranslate
$h = [K17]::Find([uint32]$p.Id, '设置')
if ($h -eq [IntPtr]::Zero) { Write-Output 'SETTINGS: missing'; exit 1 }
$win = [System.Windows.Automation.AutomationElement]::FromHandle($h)

$liCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::ListItem)
$items = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $liCond)
$target = $null
foreach ($i in $items) {
    if ($i.Current.Name -like 'hello*') { $target = $i }
}
if ($null -eq $target) { Write-Output 'ITEM hello: missing'; exit 1 }
Write-Output ("ITEM: {0}" -f $target.Current.Name)

$btnCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Button)
$btns = $target.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCond)
Write-Output ("ITEM BUTTONS: {0}" -f $btns.Count)
foreach ($b in $btns) { Write-Output ("  help='{0}'" -f $b.Current.HelpText) }

$del = $null
foreach ($b in $btns) { if ($b.Current.HelpText -eq '删除') { $del = $b } }
if ($del) {
    $del.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    Write-Output 'DELETE: invoked'
} else { Write-Output 'DELETE: button missing' }
Start-Sleep -Milliseconds 1200

Write-Output ("AFTER DELETE: " + ((Get-Content $json -Raw) -replace "`r?`n", ' '))

# 清空
$clearCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::NameProperty, '清空')
$clear = $win.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $clearCond)
if ($clear) {
    $clear.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    Write-Output 'CLEAR: invoked'
    Start-Sleep -Milliseconds 1200
    Write-Output ("AFTER CLEAR: " + ((Get-Content $json -Raw) -replace "`r?`n", ' '))
} else { Write-Output 'CLEAR: button missing' }
