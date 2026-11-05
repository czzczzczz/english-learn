# 验证②：框选空白区域（OCR 无结果）后主窗口是否恢复；③遮罩渲染是否正常
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing, System.Windows.Forms

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class EmptyOcr {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint d1, uint d2, uint d3, IntPtr e);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
  public static IntPtr Find(uint pid, string title){
    IntPtr f = IntPtr.Zero;
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid){ var sb=new StringBuilder(512); GetWindowText(h,sb,512); if(sb.ToString()==title){ f=h; return false; } } return true; }, IntPtr.Zero);
    return f;
  }
  public static bool HasOverlay(uint pid){
    bool found = false;
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid && IsWindowVisible(h)){ var sb=new StringBuilder(512); GetWindowText(h,sb,512); if(sb.ToString()=="STranslateRegionOverlay") found=true; } return true; }, IntPtr.Zero);
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
$h = [EmptyOcr]::Find([uint32]$p.Id, 'STranslate')
if ($h -eq [IntPtr]::Zero) { Write-Output 'main missing'; exit 1 }

[void][EmptyOcr]::ShowWindow($h, 5)
Start-Sleep -Milliseconds 600
Write-Output ("主窗口可见(开始): {0}" -f [EmptyOcr]::IsWindowVisible($h))

[EmptyOcr]::PressAltQ()
Start-Sleep -Milliseconds 1000
Write-Output ("遮罩出现: {0}" -f [EmptyOcr]::HasOverlay([uint32]$p.Id))

# 框一块纯色区域（屏幕左上角工具栏附近通常是纯色）
[EmptyOcr]::SetCursorPos(1200, 950)
Start-Sleep -Milliseconds 200
[EmptyOcr]::mouse_event(0x0002,0,0,0,[IntPtr]::Zero)
Start-Sleep -Milliseconds 80
for ($i = 0; $i -lt 20; $i++) { [EmptyOcr]::mouse_event(0x0001,10,0,0,[IntPtr]::Zero); Start-Sleep -Milliseconds 15 }
for ($i = 0; $i -lt 4; $i++) { [EmptyOcr]::mouse_event(0x0001,0,8,0,[IntPtr]::Zero); Start-Sleep -Milliseconds 15 }
Start-Sleep -Milliseconds 100
[EmptyOcr]::mouse_event(0x0004,0,0,0,[IntPtr]::Zero)
Write-Output '已框选空白区域'

Start-Sleep -Seconds 3
Write-Output ("② 主窗口恢复可见: {0}  (期望 True)" -f [EmptyOcr]::IsWindowVisible($h))
Write-Output ("遮罩已关闭: {0}  (期望 True)" -f (-not [EmptyOcr]::HasOverlay([uint32]$p.Id)))
