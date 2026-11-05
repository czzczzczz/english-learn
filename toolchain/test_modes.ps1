# 点击头栏方式二/方式三按钮，检查置顶位与图钉状态是否跟随
Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class ModeTest {
  public delegate bool EP(IntPtr h, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern long GetWindowLongPtr(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint a,uint b,uint c,IntPtr e);
  public const uint LD=0x0002, LU=0x0004;
  public static IntPtr Find(uint pid,string t){ IntPtr f=IntPtr.Zero; EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid){var sb=new StringBuilder(256); GetWindowText(h,sb,256); if(sb.ToString()==t){f=h;return false;}} return true;}, IntPtr.Zero); return f;}
  public static bool Topmost(IntPtr h) => ((long)GetWindowLongPtr(h,-20) & 0x8) != 0;
  public static void Click(int x,int y){ SetCursorPos(x,y); System.Threading.Thread.Sleep(150); mouse_event(LD,0,0,0,IntPtr.Zero); mouse_event(LU,0,0,0,IntPtr.Zero); }
}
"@
$p = Get-Process STranslate
$h = [ModeTest]::Find([uint32]$p.Id, "STranslate")
$r = New-Object ModeTest+RECT
[void][ModeTest]::GetWindowRect($h, [ref]$r)
$w = $r.R - $r.L
Write-Host "rect=$($r.L),$($r.T) width=$w topmostStart=$([ModeTest]::Topmost($h))"

# 头栏图标从右到左：设置、主题、方式三、方式二
$y = $r.T + 24
$gearX = $r.R - 26
$paletteX = $r.R - 60
$mode3X = $r.R - 94
$mode2X = $r.R - 128

Write-Host "click 方式三 ($mode3X,$y)"
[ModeTest]::Click($mode3X, $y)
Start-Sleep -Milliseconds 800
Write-Host "  topmost=$([ModeTest]::Topmost($h))"
Start-Sleep -Milliseconds 500

Write-Host "click 方式二 ($mode2X,$y)"
[ModeTest]::Click($mode2X, $y)
Start-Sleep -Milliseconds 800
Write-Host "  topmost=$([ModeTest]::Topmost($h))"
