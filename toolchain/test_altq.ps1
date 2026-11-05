# 实测 Alt+Q 框选识别 + 生词本词典补全
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing, System.Windows.Forms

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class AltQ {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint d1, uint d2, uint d3, IntPtr e);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
  public static bool HasOverlay(uint pid){
    bool found = false;
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid){ var sb=new StringBuilder(512); GetWindowText(h,sb,512); if(sb.ToString()=="STranslateRegionOverlay") found=true; } return true; }, IntPtr.Zero);
    return found;
  }
  public static void PressAltQ(){
    keybd_event(0x12,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x51,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(80);
    keybd_event(0x51,0,2,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x12,0,2,IntPtr.Zero);
  }
}
"@

$p = Get-Process STranslate

# 准备带英文的记事本
$np = Start-Process 'C:\Windows\System32\notepad.exe' -PassThru
Start-Sleep -Seconds 2
[void][AltQ]::SetWindowPos($np.MainWindowHandle, [IntPtr]::Zero, 200, 300, 900, 300, 0x0040)
Start-Sleep -Milliseconds 400
[void][AltQ]::SetForegroundWindow($np.MainWindowHandle)
Start-Sleep -Milliseconds 600
Set-Clipboard -Value 'campaign translation vocabulary'
(New-Object -ComObject WScript.Shell).SendKeys('^v')
Start-Sleep -Milliseconds 900

# 按 Alt+Q
[AltQ]::PressAltQ()
Start-Sleep -Milliseconds 1200
Write-Output ("A. Alt+Q -> overlay={0}  (期望 True)" -f [AltQ]::HasOverlay([uint32]$p.Id))

# 在遮罩上框选文字（记事本正文区域，避开标题/菜单）
[AltQ]::SetCursorPos(215, 372)
Start-Sleep -Milliseconds 250
[AltQ]::mouse_event(0x0002,0,0,0,[IntPtr]::Zero)
Start-Sleep -Milliseconds 100
for ($i = 0; $i -lt 40; $i++) { [AltQ]::mouse_event(0x0001,12,0,0,[IntPtr]::Zero); Start-Sleep -Milliseconds 16 }
for ($i = 0; $i -lt 4; $i++) { [AltQ]::mouse_event(0x0001,0,7,0,[IntPtr]::Zero); Start-Sleep -Milliseconds 18 }
Start-Sleep -Milliseconds 120
[AltQ]::mouse_event(0x0004,0,0,0,[IntPtr]::Zero)
Write-Output 'B. framed selection, waiting OCR...'
Start-Sleep -Seconds 4

Write-Output ("C. overlay after finish={0}  (期望 False)" -f [AltQ]::HasOverlay([uint32]$p.Id))
Stop-Process -Id $np.Id -Force -ErrorAction SilentlyContinue
