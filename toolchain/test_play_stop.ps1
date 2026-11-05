$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class V20 {
  public delegate bool EP(IntPtr h, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
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
  public static int[] Rect(IntPtr h){ RECT r; GetWindowRect(h, out r); return new int[]{ r.L, r.T, r.R, r.B }; }
  public static bool Snap(IntPtr h, IntPtr hdc){ return PrintWindow(h, hdc, 2); }
}
"@

$logPath = 'D:\vibe_coding\STranslate-dev\PortableConfig\Logs\1.0.0'
$logFile = Get-ChildItem $logPath -Filter *.log | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$base = (Get-Content $logFile.FullName).Count
Write-Output ("LOG: {0} lines={1}" -f $logFile.Name, $base)

$p = Get-Process STranslate
$main = [V20]::Find([uint32]$p.Id, 'STranslate')
[void][V20]::ShowWindow($main, 5)
Start-Sleep -Milliseconds 300
[V20]::AltG()
Start-Sleep -Milliseconds 1800
[void][V20]::SetForegroundWindow($main)
Start-Sleep -Milliseconds 900

$win = $null
$rootEl = [System.Windows.Automation.AutomationElement]::RootElement
$pc = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
for ($i = 0; $i -lt 15; $i++) {
    foreach ($w in $rootEl.FindAll([System.Windows.Automation.TreeScope]::Children, $pc)) {
        if ($w.Current.Name -eq 'STranslate') { $win = $w }
    }
    if ($null -ne $win) { break }
    Start-Sleep -Milliseconds 300
}
if ($null -eq $win) { Write-Output 'UIA MAIN: missing'; exit 1 }
Write-Output 'UIA MAIN: found'
$editCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Edit)
$edit = $null
for ($i = 0; $i -lt 12; $i++) {
    $edit = $win.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $editCond)
    if ($null -ne $edit) { break }
    Start-Sleep -Milliseconds 300
}
if ($null -eq $edit) { Write-Output 'EDIT: missing'; exit 1 }
Write-Output 'EDIT: found'

# 1) 不在生词本的词 → 空心书签
$edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('internationalization')
Start-Sleep -Milliseconds 900
$btnCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Button)
$btns = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCond)
foreach ($b in $btns) { if ($b.Current.HelpText -match '生词本') { Write-Output ("BOOKMARK(not in): '{0}'" -f $b.Current.HelpText) } }

$r = [V20]::Rect($main); $w = $r[2]-$r[0]; $h = $r[3]-$r[1]
$bmp = New-Object System.Drawing.Bitmap($w, $h); $g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc(); $ok = [V20]::Snap($main, $hdc); $g.ReleaseHdc($hdc); $g.Dispose()
$bmp.Save('D:\vibe_coding\english_learn\toolchain\vocab_btn_off.png', [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
Write-Output 'SHOT off'

# 2) 点朗读，观察是否出现停止按钮
$btnsFresh = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCond)
Write-Output ("BUTTON COUNT: {0}" -f $btnsFresh.Count)
foreach ($b in $btnsFresh) { if ($b.Current.HelpText) { Write-Output ("  help='{0}'" -f $b.Current.HelpText) } }
$play = $null
foreach ($b in $btnsFresh) { if ($b.Current.HelpText -match '播放发音') { $play = $b; break } }
if ($null -eq $play) { Write-Output 'PLAY BUTTON: missing'; exit 1 }
$play.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
Write-Output 'PLAY: invoked'
Start-Sleep -Milliseconds 1200

$btns2 = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCond)
$stop = $null
foreach ($b in $btns2) {
    if ($b.Current.HelpText -eq '取消') { $stop = $b }
}
Write-Output ("STOP BUTTON VISIBLE: {0}" -f ($null -ne $stop))

if ($stop) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $stop.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    Write-Output 'STOP: invoked'
    $back = $false
    for ($k = 0; $k -lt 30; $k++) {
        Start-Sleep -Milliseconds 100
        $now = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCond)
        $hasPlay = $false; $hasStop = $false
        foreach ($b in $now) {
            if ($b.Current.HelpText -match '播放发音') { $hasPlay = $true }
            if ($b.Current.HelpText -eq '取消') { $hasStop = $true }
        }
        if ($hasPlay -and -not $hasStop) { $back = $true; break }
    }
    $sw.Stop()
    Write-Output ("CANCEL EFFECT: back to play button = {0} after {1} ms" -f $back, $sw.ElapsedMilliseconds)
}
Start-Sleep -Milliseconds 4000

Write-Output '=== 新增日志 ==='
Get-Content $logFile.FullName | Select-Object -Skip $base |
    Where-Object { $_.Length -lt 300 -and $_ -match 'AudioPlayer|dictvoice|TtsCancelled|TTS' } |
    Select-Object -First 15
