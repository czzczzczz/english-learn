$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class V24 {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
  public static void AltG(){
    keybd_event(0x12,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x47,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x47,0,2,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x12,0,2,IntPtr.Zero);
  }
  public static IntPtr Find(uint pid, string title){
    IntPtr f = IntPtr.Zero;
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid){ var sb=new StringBuilder(512); GetWindowText(h,sb,512); if(sb.ToString()==title){ f=h; return false; } } return true; }, IntPtr.Zero);
    return f;
  }
}
"@

$p = Get-Process STranslate
[V24]::AltG()
Start-Sleep -Milliseconds 1600
$main = [V24]::Find([uint32]$p.Id, 'STranslate')
[void][V24]::SetForegroundWindow($main)
Start-Sleep -Milliseconds 800

$rootEl = [System.Windows.Automation.AutomationElement]::RootElement
$pc = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
$win = $null
for ($i = 0; $i -lt 15; $i++) {
    foreach ($w in $rootEl.FindAll([System.Windows.Automation.TreeScope]::Children, $pc)) {
        if ($w.Current.Name -eq 'STranslate') { $win = $w }
    }
    if ($null -ne $win) { break }
    Start-Sleep -Milliseconds 300
}
if ($null -eq $win) { Write-Output 'UIA: missing'; exit 1 }

$btnCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Button)

function Find-Play($w) {
    foreach ($b in $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCond)) {
        if ($b.Current.HelpText -match '播放发音') { return $b }
    }
    return $null
}
function Find-Stop($w) {
    foreach ($b in $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCond)) {
        if ($b.Current.HelpText -eq '取消') { return $b }
    }
    return $null
}

$play = Find-Play $win
if ($null -eq $play) { Write-Output 'PLAY: missing'; exit 1 }
$play.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
Write-Output 'PLAY: invoked'
Start-Sleep -Milliseconds 700

$stop = Find-Stop $win
Write-Output ("STOP VISIBLE after 700ms: {0}" -f ($null -ne $stop))
if ($null -eq $stop) { exit 0 }

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$stop.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()

# 点击取消后，命令 IsRunning 应立即结束，按钮回到"播放发音"
$back = $false
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 100
    if ($null -ne (Find-Play $win) -and $null -eq (Find-Stop $win)) { $back = $true; break }
}
$sw.Stop()
Write-Output ("CANCEL EFFECT: play button back = {0} after {1} ms" -f $back, $sw.ElapsedMilliseconds)
