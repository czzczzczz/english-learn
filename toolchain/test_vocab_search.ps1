$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class K16 {
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

$p = Get-Process STranslate
$h = [K16]::Find([uint32]$p.Id, '设置')
if ($h -eq [IntPtr]::Zero) { Write-Output 'SETTINGS: missing'; exit 1 }
$win = [System.Windows.Automation.AutomationElement]::FromHandle($h)

function Get-ListItems($rootEl) {
    $c = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::ListItem)
    return $rootEl.FindAll([System.Windows.Automation.TreeScope]::Descendants, $c)
}

$before = Get-ListItems $win
Write-Output ("LIST ITEMS BEFORE: {0}" -f $before.Count)

$editCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Edit)
$edit = $win.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $editCond)
if ($null -eq $edit) { Write-Output 'SEARCH BOX: missing'; exit 1 }
$edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('wor')
Write-Output 'SEARCH: wor'
Start-Sleep -Milliseconds 1200

$after = Get-ListItems $win
Write-Output ("LIST ITEMS AFTER: {0}" -f $after.Count)
foreach ($i in $after) { Write-Output ("  item: {0}" -f $i.Current.Name) }

# 清空搜索，恢复列表
$edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('')
Start-Sleep -Milliseconds 800
$restored = Get-ListItems $win
Write-Output ("LIST ITEMS RESTORED: {0}" -f $restored.Count)
