$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class W2 {
  public delegate bool EP(IntPtr h, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint f);
  public static IntPtr FindVisible(uint pid, string title){
    IntPtr f=IntPtr.Zero;
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid && IsWindowVisible(h)){var sb=new StringBuilder(512); GetWindowText(h,sb,512); if(sb.ToString()==title){f=h;return false;}} return true;}, IntPtr.Zero);
    return f;
  }
  public static int[] Rect(IntPtr h){ RECT r; GetWindowRect(h, out r); return new int[]{ r.L, r.T, r.R, r.B }; }
  public static bool Snap(IntPtr h, IntPtr hdc){ return PrintWindow(h, hdc, 2); }
}
"@
# 用全局热键 Alt+G 唤出主窗口
[System.Windows.Forms.SendKeys]::SendWait('%g')
Start-Sleep -Milliseconds 1500
$p = Get-Process STranslate
$h = [W2]::FindVisible([uint32]$p.Id, 'STranslate')
if ($h -eq [IntPtr]::Zero) { Write-Output 'MAIN: still hidden'; exit 0 }
$r = [W2]::Rect($h); $w = $r[2]-$r[0]; $ht = $r[3]-$r[1]
Write-Output ("MAIN: rect={0},{1} {2}x{3}" -f $r[0],$r[1],$w,$ht)
$bmp = New-Object System.Drawing.Bitmap($w,$ht); $g = [System.Drawing.Graphics]::FromImage($bmp); $hdc = $g.GetHdc()
$ok = [W2]::Snap($h, $hdc); $g.ReleaseHdc($hdc); $g.Dispose()
$out = 'D:\vibe_coding\english_learn\toolchain\main_shown.png'
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
Write-Output ("SNAP ok={0} -> {1} ({2:N0} bytes)" -f $ok, $out, (Get-Item $out).Length)
