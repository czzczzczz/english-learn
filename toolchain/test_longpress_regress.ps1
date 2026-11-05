# 回归：快速单击不触发遮罩；拖选文字仍走划词
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class Regress {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint d1, uint d2, uint d3, IntPtr e);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X,Y; }
  public static bool HasOverlay(uint pid){
    bool found = false;
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid && IsWindowVisible(h)){ var sb=new StringBuilder(512); GetWindowText(h,sb,512); if(sb.ToString()=="STranslateRegionOverlay") found=true; } return true; }, IntPtr.Zero);
    return found;
  }
  public static IntPtr Find(uint pid, string title){
    IntPtr f = IntPtr.Zero;
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid){ var sb=new StringBuilder(512); GetWindowText(h,sb,512); if(sb.ToString()==title){ f=h; return false; } } return true; }, IntPtr.Zero);
    return f;
  }
}
"@

$p = Get-Process STranslate

# 记事本准备文本
$np = Start-Process 'C:\Windows\System32\notepad.exe' -PassThru
Start-Sleep -Seconds 2
[void][Regress]::SetWindowPos($np.MainWindowHandle, [IntPtr]::Zero, 150, 400, 900, 240, 0x0040)
Start-Sleep -Milliseconds 400
[void][Regress]::SetForegroundWindow($np.MainWindowHandle)
Start-Sleep -Milliseconds 600
Set-Clipboard -Value 'campaign translation vocabulary'
(New-Object -ComObject WScript.Shell).SendKeys('^v')
Start-Sleep -Milliseconds 800

$pt = New-Object Regress+POINT
[void][Regress]::ClientToScreen($np.MainWindowHandle, [ref]$pt)
$sx = $pt.X + 45
$sy = $pt.Y + 40

# 1) 快速单击（150ms 内松开）
[Regress]::SetCursorPos($sx, $sy)
Start-Sleep -Milliseconds 250
[Regress]::mouse_event(0x0002,0,0,0,[IntPtr]::Zero)
Start-Sleep -Milliseconds 120
[Regress]::mouse_event(0x0004,0,0,0,[IntPtr]::Zero)
Start-Sleep -Milliseconds 800
Write-Output ("A. 快速单击 -> overlay={0}  (期望 False)" -f [Regress]::HasOverlay([uint32]$p.Id))

# 2) 拖选（立即移动，不等长按）
[Regress]::SetCursorPos($sx, $sy)
Start-Sleep -Milliseconds 250
[Regress]::mouse_event(0x0002,0,0,0,[IntPtr]::Zero)
Start-Sleep -Milliseconds 60
for ($i = 0; $i -lt 8; $i++) { [Regress]::mouse_event(0x0001,8,0,0,[IntPtr]::Zero); Start-Sleep -Milliseconds 30 }
[Regress]::mouse_event(0x0004,0,0,0,[IntPtr]::Zero)
Start-Sleep -Milliseconds 1200
Write-Output ("B. 拖选划词 -> overlay={0}  (期望 False)" -f [Regress]::HasOverlay([uint32]$p.Id))

Stop-Process -Id $np.Id -Force -ErrorAction SilentlyContinue
