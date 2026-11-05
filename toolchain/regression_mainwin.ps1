$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class Enum9 {
  public delegate bool EP(IntPtr h, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);

  public static string[] List(uint pid) {
    string[] res = new string[32]; int i = 0;
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid){ var sb=new StringBuilder(512); GetWindowText(h,sb,512); if(sb.Length>0 && i<32) { res[i] = "vis=" + IsWindowVisible(h) + " title='" + sb.ToString() + "'"; i++; } } return true; }, IntPtr.Zero);
    string[] outArr = new string[i];
    Array.Copy(res, outArr, i);
    return outArr;
  }
  public static IntPtr FindVisible(uint pid, string title){
    IntPtr f=IntPtr.Zero;
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid && IsWindowVisible(h)){var sb=new StringBuilder(512); GetWindowText(h,sb,512); if(sb.ToString()==title){f=h;return false;}} return true;}, IntPtr.Zero);
    return f;
  }
  public static int[] Rect(IntPtr h){ RECT r; GetWindowRect(h, out r); return new int[]{ r.L, r.T, r.R, r.B }; }
  public static bool Snap(IntPtr h, IntPtr hdc){ return PrintWindow(h, hdc, 2); }
}
"@

$p = Get-Process STranslate
Write-Output '=== 窗口列表 ==='
[Enum9]::List([uint32]$p.Id) | ForEach-Object { Write-Output ("  " + $_) }

$h = [Enum9]::FindVisible([uint32]$p.Id, 'STranslate')
if ($h -eq [IntPtr]::Zero) { Write-Output 'MAIN WINDOW: not visible'; exit 0 }

$r = [Enum9]::Rect($h)
$w = $r[2] - $r[0]; $ht = $r[3] - $r[1]
$bmp = New-Object System.Drawing.Bitmap($w, $ht)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
$ok = [Enum9]::Snap($h, $hdc)
$g.ReleaseHdc($hdc); $g.Dispose()
$out = 'D:\vibe_coding\english_learn\toolchain\rg3_translate.png'
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
Write-Output ("MAIN SNAP {0}x{1} printWindow={2} -> {3} ({4:N0} bytes)" -f $w, $ht, $ok, $out, (Get-Item $out).Length)
