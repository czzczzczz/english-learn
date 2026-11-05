# 钉住后点击真实窗口（记事本），检查主窗口是否被隐藏
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class RealClick {
  public delegate bool EP(IntPtr h, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern long GetWindowLongPtr(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint d1, uint d2, uint d3, IntPtr e);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
  public static IntPtr Find(uint pid, string title){
    IntPtr f = IntPtr.Zero;
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid){ var sb=new StringBuilder(512); GetWindowText(h,sb,512); if(sb.ToString()==title){ f=h; return false; } } return true; }, IntPtr.Zero);
    return f;
  }
  public static int[] Rect(IntPtr h){ RECT r; GetWindowRect(h, out r); return new int[]{ r.L, r.T, r.R, r.B }; }
  public static bool Topmost(IntPtr h){ return ((long)GetWindowLongPtr(h, -20) & 0x8) != 0; }
  public static void Click(int x, int y){
    SetCursorPos(x, y);
    System.Threading.Thread.Sleep(150);
    mouse_event(0x0002,0,0,0,IntPtr.Zero);
    System.Threading.Thread.Sleep(80);
    mouse_event(0x0004,0,0,0,IntPtr.Zero);
  }
  public static void AltG(){
    keybd_event(0x12,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x47,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x47,0,2,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x12,0,2,IntPtr.Zero);
  }
}
"@

$p = Get-Process STranslate
$h = [RealClick]::Find([uint32]$p.Id, 'STranslate')
if ($h -eq [IntPtr]::Zero) { Write-Output 'MAIN: missing'; exit 1 }

[RealClick]::AltG()
Start-Sleep -Milliseconds 1200
[void][RealClick]::ShowWindow($h, 5)
Start-Sleep -Milliseconds 300
[void][RealClick]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 700

$rootEl = [System.Windows.Automation.AutomationElement]::RootElement
$pc = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
$win = $null
for ($i = 0; $i -lt 10; $i++) {
    foreach ($w in $rootEl.FindAll([System.Windows.Automation.TreeScope]::Children, $pc)) {
        if ($w.Current.Name -eq 'STranslate') { $win = $w }
    }
    if ($null -ne $win) { break }
    Start-Sleep -Milliseconds 300
}
if ($null -eq $win) { Write-Output 'UIA: missing'; exit 1 }

function Get-PinToggle($w) {
    $c = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Button)
    foreach ($b in $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, $c)) {
        try { return $b.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern) } catch { }
    }
    return $null
}

$tp = Get-PinToggle $win
Write-Output ("PIN before: {0}  topmost={1}" -f $tp.Current.ToggleState, [RealClick]::Topmost($h))
if ($tp.Current.ToggleState -ne [System.Windows.Automation.ToggleState]::On) {
    $r = [RealClick]::Rect($h)
    [RealClick]::Click(($r[0] + 20), ($r[1] + 18))
    Start-Sleep -Milliseconds 800
    $tp = Get-PinToggle $win
    Write-Output ("PIN after click: {0}  topmost={1}" -f $tp.Current.ToggleState, [RealClick]::Topmost($h))
}

# 打开记事本并点击它
$np = Start-Process 'C:\Windows\System32\notepad.exe' -PassThru
Start-Sleep -Seconds 2
[void][RealClick]::SetWindowPos($np.MainWindowHandle, [IntPtr]::Zero, 60, 500, 700, 320, 0x0040)
Start-Sleep -Milliseconds 500
$nr = [RealClick]::Rect($np.MainWindowHandle)
Write-Output ("notepad rect: {0},{1}" -f $nr[0], $nr[1])
[RealClick]::Click(($nr[0] + 200), ($nr[1] + 60))
Start-Sleep -Milliseconds 1500

$vis = [RealClick]::IsWindowVisible($h)
$top = [RealClick]::Topmost($h)
$tp2 = Get-PinToggle $win
Write-Output ("AFTER CLICK NOTEPAD: visible={0} topmost={1} pin={2}" -f $vis, $top, $(if ($tp2) { $tp2.Current.ToggleState } else { 'n/a' }))

Stop-Process -Id $np.Id -Force -ErrorAction SilentlyContinue
