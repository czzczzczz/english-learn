$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class K1 {
  public delegate bool EP(IntPtr h, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint f);
  public const uint KU = 0x0002;
  public static void AltKey(byte vk){ keybd_event(0x12,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(60); keybd_event(vk,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(60); keybd_event(vk,0,KU,IntPtr.Zero); System.Threading.Thread.Sleep(40); keybd_event(0x12,0,KU,IntPtr.Zero); }
  public static IntPtr Find(uint pid, string title){ IntPtr f=IntPtr.Zero; EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid){var sb=new StringBuilder(512); GetWindowText(h,sb,512); if(sb.ToString()==title){f=h;return false;}} return true;}, IntPtr.Zero); return f; }
  public static int[] Rect(IntPtr h){ RECT r; GetWindowRect(h, out r); return new int[]{ r.L,r.T,r.R,r.B }; }
  public static bool Snap(IntPtr h, IntPtr hdc){ return PrintWindow(h, hdc, 2); }
}
"@
$app = Get-Process STranslate | Select-Object -First 1
$h = [K1]::Find([uint32]$app.Id, 'STranslate')
if ($h -eq [IntPtr]::Zero) { Write-Output 'window missing'; exit 1 }
$before = [K1]::Rect($h)
Write-Output ("before: {0},{1} {2}x{3} vis={4}" -f $before[0],$before[1],($before[2]-$before[0]),($before[3]-$before[1]),[K1]::IsWindowVisible($h))
# 先把窗口藏起来，验证 Alt+D 能唤出/触发
[void][K1]::ShowWindow($h, 0)
Start-Sleep -Milliseconds 700
Write-Output ("hidden vis={0}" -f [K1]::IsWindowVisible($h))
[K1]::AltKey(0x44)  # Alt + D
Start-Sleep -Seconds 2
$h2 = [K1]::Find([uint32]$app.Id, 'STranslate')
$after = [K1]::Rect($h2)
Write-Output ("after Alt+D: {0},{1} {2}x{3} vis={4}" -f $after[0],$after[1],($after[2]-$after[0]),($after[3]-$after[1]),[K1]::IsWindowVisible($h2))
if ([K1]::IsWindowVisible($h2)) {
  $w = $after[2]-$after[0]; $ht = $after[3]-$after[1]
  if ($w -gt 0 -and $ht -gt 0) {
    $bmp = New-Object System.Drawing.Bitmap($w,$ht); $g = [System.Drawing.Graphics]::FromImage($bmp); $hdc = $g.GetHdc()
    $ok = [K1]::Snap($h2, $hdc); $g.ReleaseHdc($hdc); $g.Dispose()
    $out = 'D:\vibe_coding\english_learn\toolchain\altd_window.png'
    $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    Write-Output ("snap ok={0} -> {1} ({2:N0} bytes)" -f $ok,$out,(Get-Item $out).Length)
  }
}
Write-Output '=== log tail ==='
Get-Content 'D:\vibe_coding\STranslate-dev\PortableConfig\Logs\1.0.0\20261103.log' -Tail 8 | ForEach-Object { Write-Output $_ }
