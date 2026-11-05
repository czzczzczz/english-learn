# 钉住后点击多处外部区域；并截图对比钉子 On/Off 的视觉效果
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class MultiClick {
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
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
  public static IntPtr Find(uint pid, string title){
    IntPtr f = IntPtr.Zero;
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid){ var sb=new StringBuilder(512); GetWindowText(h,sb,512); if(sb.ToString()==title){ f=h; return false; } } return true; }, IntPtr.Zero);
    return f;
  }
  public static int[] Rect(IntPtr h){ RECT r; GetWindowRect(h, out r); return new int[]{ r.L, r.T, r.R, r.B }; }
  public static bool Topmost(IntPtr h){ return ((long)GetWindowLongPtr(h, -20) & 0x8) != 0; }
  public static bool Snap(IntPtr h, IntPtr hdc){ return PrintWindow(h, hdc, 2); }
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
$h = [MultiClick]::Find([uint32]$p.Id, 'STranslate')
if ($h -eq [IntPtr]::Zero) { Write-Output 'MAIN: missing'; exit 1 }

function Show-Main {
    [MultiClick]::AltG()
    Start-Sleep -Milliseconds 1200
    [void][MultiClick]::ShowWindow($h, 5)
    Start-Sleep -Milliseconds 300
    [void][MultiClick]::SetForegroundWindow($h)
    Start-Sleep -Milliseconds 700
}

function Snap-Pin($tag) {
    $r = [MultiClick]::Rect($h)
    $w = $r[2] - $r[0]; $ht = $r[3] - $r[1]
    $bmp = New-Object System.Drawing.Bitmap($w, 70)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc()
    $ok = [MultiClick]::Snap($h, $hdc)
    $g.ReleaseHdc($hdc); $g.Dispose()
    $out = "D:\vibe_coding\english_learn\toolchain\pin_$tag.png"
    $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    Write-Output ("  shot pin_$tag.png (${w}x70) ok=$ok")
}

Show-Main
$r = [MultiClick]::Rect($h)
Write-Output ("start topmost={0}" -f [MultiClick]::Topmost($h))

if ([MultiClick]::Topmost($h)) {
    [MultiClick]::Click(($r[0] + 20), ($r[1] + 18))
    Start-Sleep -Milliseconds 800
}
Snap-Pin 'off'
Write-Output ("state OFF: topmost={0}" -f [MultiClick]::Topmost($h))

[MultiClick]::Click(($r[0] + 20), ($r[1] + 18))
Start-Sleep -Milliseconds 900
Snap-Pin 'on'
Write-Output ("state ON: topmost={0}" -f [MultiClick]::Topmost($h))

$points = @(
    @{ name = 'desktop-left'; x = 1200; y = 700 },
    @{ name = 'taskbar'; x = 960; y = 1065 },
    @{ name = 'top-area'; x = 300; y = 40 }
)

foreach ($pt in $points) {
    [MultiClick]::Click($pt.x, $pt.y)
    Start-Sleep -Milliseconds 1200
    $vis = [MultiClick]::IsWindowVisible($h)
    $top = [MultiClick]::Topmost($h)
    Write-Output ("click {0} ({1},{2}) -> visible={3} topmost={4}" -f $pt.name, $pt.x, $pt.y, $vis, $top)
}
