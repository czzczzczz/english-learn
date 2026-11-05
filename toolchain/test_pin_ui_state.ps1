# 读钉子按钮的 ToggleState，对照窗口 WS_EX_TOPMOST，定位"UI 灭了但窗口还钉着"
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class PinUi {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern long GetWindowLongPtr(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
  public static IntPtr Find(uint pid, string title){
    IntPtr f = IntPtr.Zero;
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid){ var sb=new StringBuilder(512); GetWindowText(h,sb,512); if(sb.ToString()==title){ f=h; return false; } } return true; }, IntPtr.Zero);
    return f;
  }
  public static bool Topmost(IntPtr h){ return ((long)GetWindowLongPtr(h, -20) & 0x8) != 0; }
  public static void AltG(){
    keybd_event(0x12,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x47,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x47,0,2,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x12,0,2,IntPtr.Zero);
  }
  public static void CtrlShiftT(){
    keybd_event(0x11,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(50);
    keybd_event(0x10,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(50);
    keybd_event(0x54,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(50);
    keybd_event(0x54,0,2,IntPtr.Zero); System.Threading.Thread.Sleep(50);
    keybd_event(0x10,0,2,IntPtr.Zero); System.Threading.Thread.Sleep(50);
    keybd_event(0x11,0,2,IntPtr.Zero);
  }
}
"@

$p = Get-Process STranslate
$h = [PinUi]::Find([uint32]$p.Id, 'STranslate')
[PinUi]::AltG()
Start-Sleep -Milliseconds 1000
[void][PinUi]::ShowWindow($h, 5)
Start-Sleep -Milliseconds 300
[void][PinUi]::SetForegroundWindow($h)
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
if ($null -eq $win) { Write-Output 'UIA: main missing'; exit 1 }

function Get-ToggleState($w) {
    $c = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Button)
    foreach ($b in $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, $c)) {
        try {
            $tp = $b.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
            $r = $b.Current.BoundingRectangle
            return ("toggle={0} at {1:N0},{2:N0}" -f $tp.Current.ToggleState, $r.X, $r.Y)
        } catch { }
    }
    return 'no toggle button'
}

Write-Output ("STEP0  ui=[{0}]  hwndTopmost={1}" -f (Get-ToggleState $win), [PinUi]::Topmost($h))

for ($i = 1; $i -le 4; $i++) {
    [PinUi]::AltG()
    Start-Sleep -Milliseconds 900
    [void][PinUi]::ShowWindow($h, 5)
    Start-Sleep -Milliseconds 300
    [PinUi]::CtrlShiftT()
    Start-Sleep -Milliseconds 900
    Write-Output ("STEP{0}  ui=[{1}]  hwndTopmost={2}" -f $i, (Get-ToggleState $win), [PinUi]::Topmost($h))
}
