# Alt+Q 可控验证：记事本放左上角、字号大，框选正文首行
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class AltQ2 {
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
    keybd_event(0x51,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(90);
    keybd_event(0x51,0,2,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x12,0,2,IntPtr.Zero);
  }
}
"@

$p = Get-Process STranslate

# 记事本放左上角，写三行大字英文
$np = Start-Process 'C:\Windows\System32\notepad.exe' -PassThru
Start-Sleep -Seconds 2
[void][AltQ2]::SetWindowPos($np.MainWindowHandle, [IntPtr]::Zero, 40, 40, 780, 340, 0x0040)
Start-Sleep -Milliseconds 500
[void][AltQ2]::SetForegroundWindow($np.MainWindowHandle)
Start-Sleep -Milliseconds 700
(New-Object -ComObject WScript.Shell).SendKeys('^a')
Start-Sleep -Milliseconds 200
Set-Clipboard -Value "Learning English is easier`r`nwhen you listen every day."
(New-Object -ComObject WScript.Shell).SendKeys('^v')
Start-Sleep -Milliseconds 600
Start-Sleep -Milliseconds 800

[AltQ2]::PressAltQ()
Start-Sleep -Milliseconds 1200
Write-Output ("overlay={0}" -f [AltQ2]::HasOverlay([uint32]$p.Id))

# 框选记事本正文（左上区域内一块）
[AltQ2]::SetCursorPos(55, 95)
Start-Sleep -Milliseconds 250
[AltQ2]::mouse_event(0x0002,0,0,0,[IntPtr]::Zero)
Start-Sleep -Milliseconds 90
for ($i = 0; $i -lt 45; $i++) { [AltQ2]::mouse_event(0x0001,14,0,0,[IntPtr]::Zero); Start-Sleep -Milliseconds 14 }
for ($i = 0; $i -lt 5; $i++) { [AltQ2]::mouse_event(0x0001,0,8,0,[IntPtr]::Zero); Start-Sleep -Milliseconds 16 }
Start-Sleep -Milliseconds 120
[AltQ2]::mouse_event(0x0004,0,0,0,[IntPtr]::Zero)
Write-Output 'selection done'
Start-Sleep -Seconds 4
Write-Output ("overlay after={0}" -f [AltQ2]::HasOverlay([uint32]$p.Id))
Stop-Process -Id $np.Id -Force -ErrorAction SilentlyContinue
