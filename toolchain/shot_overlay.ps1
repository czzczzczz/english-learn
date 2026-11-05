# 抓一张框选遮罩的截图，然后按 Esc 取消
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing, System.Windows.Forms

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class ShotOverlay {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint d1, uint d2, uint d3, IntPtr e);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
  public static bool HasOverlay(uint pid){
    bool found = false;
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid){ var sb=new StringBuilder(512); GetWindowText(h,sb,512); if(sb.ToString()=="STranslateRegionOverlay") found=true; } return true; }, IntPtr.Zero);
    return found;
  }
  public static void Esc(){ keybd_event(0x1B,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(60); keybd_event(0x1B,0,2,IntPtr.Zero); }
}
"@

$p = Get-Process STranslate

# 长按进入遮罩
[ShotOverlay]::SetCursorPos(400, 400)
Start-Sleep -Milliseconds 300
[ShotOverlay]::mouse_event(0x0002,0,0,0,[IntPtr]::Zero)
Start-Sleep -Milliseconds 750
[ShotOverlay]::mouse_event(0x0004,0,0,0,[IntPtr]::Zero)
Start-Sleep -Milliseconds 700
Write-Output ("overlay present: {0}" -f [ShotOverlay]::HasOverlay([uint32]$p.Id))

# 在遮罩上拖一个框，停在拖拽中截图
[ShotOverlay]::SetCursorPos(300, 300)
Start-Sleep -Milliseconds 200
[ShotOverlay]::mouse_event(0x0002,0,0,0,[IntPtr]::Zero)
Start-Sleep -Milliseconds 80
for ($i = 0; $i -lt 25; $i++) { [ShotOverlay]::mouse_event(0x0001,14,0,0,[IntPtr]::Zero); Start-Sleep -Milliseconds 15 }
for ($i = 0; $i -lt 8; $i++) { [ShotOverlay]::mouse_event(0x0001,0,10,0,[IntPtr]::Zero); Start-Sleep -Milliseconds 15 }
Start-Sleep -Milliseconds 250

$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
$g.Dispose()
$out = 'D:\vibe_coding\english_learn\toolchain\overlay_preview.png'
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output ("shot -> {0} ({1:N0} bytes)" -f $out, (Get-Item $out).Length)

# 取消：先松开，再 Esc
[ShotOverlay]::mouse_event(0x0004,0,0,0,[IntPtr]::Zero)
Start-Sleep -Milliseconds 400
[ShotOverlay]::Esc()
Start-Sleep -Milliseconds 600
Write-Output ("overlay present after esc: {0}" -f [ShotOverlay]::HasOverlay([uint32]$p.Id))
