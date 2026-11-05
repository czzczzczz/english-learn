# 复现用户场景：划词气泡翻译后，钉子是否还能正确钉住
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing, System.Windows.Forms

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class BubblePin {
  public delegate bool EP(IntPtr h, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X,Y; }
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
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
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
    System.Threading.Thread.Sleep(140);
    mouse_event(0x0002,0,0,0,IntPtr.Zero);
    System.Threading.Thread.Sleep(70);
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

function Get-Pin($pidVal) {
    $rootEl = [System.Windows.Automation.AutomationElement]::RootElement
    $pc = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $pidVal)
    $win = $null
    for ($i = 0; $i -lt 12; $i++) {
        foreach ($w in $rootEl.FindAll([System.Windows.Automation.TreeScope]::Children, $pc)) {
            if ($w.Current.Name -eq 'STranslate') { $win = $w }
        }
        if ($null -ne $win) { break }
        Start-Sleep -Milliseconds 300
    }
    if ($null -eq $win) { return 'no-window' }
    $c = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Button)
    foreach ($b in $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $c)) {
        try { return $b.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Current.ToggleState } catch { }
    }
    return 'no-toggle'
}

$p = Get-Process STranslate
$h = [BubblePin]::Find([uint32]$p.Id, 'STranslate')
if ($h -eq [IntPtr]::Zero) { Write-Output 'MAIN: missing'; exit 1 }

function Show-Main {
    [BubblePin]::AltG()
    Start-Sleep -Milliseconds 1200
    [void][BubblePin]::ShowWindow($h, 5)
    Start-Sleep -Milliseconds 300
    [void][BubblePin]::SetForegroundWindow($h)
    Start-Sleep -Milliseconds 700
}

# 1) 划词气泡翻译（模拟真实使用）
$np = Start-Process 'C:\Windows\System32\notepad.exe' -PassThru
Start-Sleep -Seconds 2
[void][BubblePin]::SetWindowPos($np.MainWindowHandle, [IntPtr]::Zero, 200, 620, 900, 300, 0x0040)
Start-Sleep -Milliseconds 400
[void][BubblePin]::SetForegroundWindow($np.MainWindowHandle)
Start-Sleep -Milliseconds 600
Set-Clipboard -Value 'campaign'
(New-Object -ComObject WScript.Shell).SendKeys('^v')
Start-Sleep -Milliseconds 800

$pt = New-Object BubblePin+POINT
[void][BubblePin]::ClientToScreen($np.MainWindowHandle, [ref]$pt)
$sx = $pt.X + 45
$sy = $pt.Y + 22
[void][BubblePin]::SetCursorPos($sx, $sy)
Start-Sleep -Milliseconds 300
[void][BubblePin]::SetCursorPos(($sx + 6), $sy)
Start-Sleep -Milliseconds 600
[BubblePin]::mouse_event(0x0002,0,0,0,[IntPtr]::Zero)
Start-Sleep -Milliseconds 60
for ($i = 0; $i -lt 6; $i++) { [BubblePin]::mouse_event(0x0001,8,0,0,[IntPtr]::Zero); Start-Sleep -Milliseconds 40 }
[BubblePin]::mouse_event(0x0004,0,0,0,[IntPtr]::Zero)
Start-Sleep -Milliseconds 700

# 悬停气泡触发翻译
[void][BubblePin]::SetCursorPos(($sx + 54 + 28), ($sy + 30))
Start-Sleep -Milliseconds 3000
Stop-Process -Id $np.Id -Force -ErrorAction SilentlyContinue

Write-Output ("AFTER BUBBLE: pin={0} visible={1} topmost={2}" -f (Get-Pin $p.Id), [BubblePin]::IsWindowVisible($h), [BubblePin]::Topmost($h))

# 2) 此时点钉子一次 → 应该钉住
$r = [BubblePin]::Rect($h)
[BubblePin]::Click(($r[0] + 20), ($r[1] + 18))
Start-Sleep -Milliseconds 900
$pin1 = Get-Pin $p.Id
$top1 = [BubblePin]::Topmost($h)
Write-Output ("CLICK 1: pin={0} topmost={1}" -f $pin1, $top1)

# 3) 钉住状态点外部
[BubblePin]::Click(1400, 800)
Start-Sleep -Milliseconds 1200
Write-Output ("  click outside while pinned: visible={0} topmost={1}" -f [BubblePin]::IsWindowVisible($h), [BubblePin]::Topmost($h))

# 4) 再点一次 → 取消
if (-not [BubblePin]::IsWindowVisible($h)) { Show-Main }
$r = [BubblePin]::Rect($h)
[BubblePin]::Click(($r[0] + 20), ($r[1] + 18))
Start-Sleep -Milliseconds 900
Write-Output ("CLICK 2: pin={0} topmost={1}" -f (Get-Pin $p.Id), [BubblePin]::Topmost($h))
