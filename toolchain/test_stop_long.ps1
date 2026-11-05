$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class V22 {
  public delegate bool EP(IntPtr h, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  public static IntPtr Find(uint pid, string title){
    IntPtr f = IntPtr.Zero;
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid){ var sb=new StringBuilder(512); GetWindowText(h,sb,512); if(sb.ToString()==title){ f=h; return false; } } return true; }, IntPtr.Zero);
    return f;
  }
}
"@

$logPath = 'D:\vibe_coding\STranslate-dev\PortableConfig\Logs\1.0.0'
$logFile = Get-ChildItem $logPath -Filter *.log | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$base = (Get-Content $logFile.FullName).Count

$p = Get-Process STranslate
$main = [V22]::Find([uint32]$p.Id, 'STranslate')
[void][V22]::ShowWindow($main, 5)
Start-Sleep -Milliseconds 800
[void][V22]::SetForegroundWindow($main)
Start-Sleep -Milliseconds 1500

$win = [System.Windows.Automation.AutomationElement]::FromHandle($main)
$editCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Edit)
$edit = $null
for ($i = 0; $i -lt 10; $i++) {
    $edit = $win.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $editCond)
    if ($null -ne $edit) { break }
    Start-Sleep -Milliseconds 300
}
if ($null -eq $edit) { Write-Output 'EDIT: still null'; exit 1 }
Write-Output 'EDIT: found'
$edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('Learning English is easier when you listen every day.')
Write-Output 'INPUT: long sentence'
Start-Sleep -Milliseconds 1200

$btnCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Button)

$play = $null
foreach ($b in $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCond)) {
    if ($b.Current.HelpText -match '播放发音') { $play = $b; break }
}
if ($null -eq $play) { Write-Output 'PLAY: missing'; exit 1 }
$play.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
Write-Output 'PLAY: invoked'
Start-Sleep -Milliseconds 1500

$stop = $null
foreach ($b in $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCond)) {
    if ($b.Current.HelpText -eq '取消') { $stop = $b }
}
Write-Output ("STOP VISIBLE: {0}" -f ($null -ne $stop))

if ($stop) {
    $stop.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    Write-Output 'STOP: invoked'
}
Start-Sleep -Milliseconds 3000

Write-Output '=== 新增日志 ==='
Get-Content $logFile.FullName | Select-Object -Skip $base |
    Where-Object { $_.Length -lt 300 -and $_ -match 'AudioPlayer|translate_tts|gettts|被取消|取消' } |
    Select-Object -First 15
