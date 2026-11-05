# 查找「生词故事」窗口并截图
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class ShotStory {
  public delegate bool EP(IntPtr h, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  public static string[] List(uint pid){
    var res = new System.Collections.Generic.List<string>();
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid && IsWindowVisible(h)){ var sb=new StringBuilder(512); GetWindowText(h,sb,512); res.Add("'" + sb.ToString() + "'"); } return true; }, IntPtr.Zero);
    return res.ToArray();
  }
  public static IntPtr Find(uint pid, string title){
    IntPtr f = IntPtr.Zero;
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid){ var sb=new StringBuilder(512); GetWindowText(h,sb,512); if(sb.ToString()==title){ f=h; return false; } } return true; }, IntPtr.Zero);
    return f;
  }
  public static int[] Rect(IntPtr h){ RECT r; GetWindowRect(h, out r); return new int[]{ r.L, r.T, r.R, r.B }; }
  public static bool Snap(IntPtr h, IntPtr hdc){ return PrintWindow(h, hdc, 2); }
}
"@

$p = Get-Process STranslate
Write-Output ("窗口: " + ([ShotStory]::List([uint32]$p.Id) -join ' / '))

$h = [ShotStory]::Find([uint32]$p.Id, '生词故事')
if ($h -eq [IntPtr]::Zero) { Write-Output '生词故事窗口未找到'; exit 0 }

$r = [ShotStory]::Rect($h)
$w = $r[2] - $r[0]; $ht = $r[3] - $r[1]
$bmp = New-Object System.Drawing.Bitmap($w, $ht)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
$ok = [ShotStory]::Snap($h, $hdc)
$g.ReleaseHdc($hdc); $g.Dispose()
$out = 'D:\vibe_coding\english_learn\toolchain\story_window.png'
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
Write-Output ("SHOT ${w}x${ht} ok=$ok -> $out")
