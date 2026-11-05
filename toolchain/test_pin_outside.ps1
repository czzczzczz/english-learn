# 复现：开置顶后点击窗口外，窗口是否被隐藏
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class PinOut {
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
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);

  public static IntPtr Find(uint pid, string title){
    IntPtr f = IntPtr.Zero;
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid){ var sb=new StringBuilder(512); GetWindowText(h,sb,512); if(sb.ToString()==title){ f=h; return false; } } return true; }, IntPtr.Zero);
    return f;
  }
  public static int[] Rect(IntPtr h){ RECT r; GetWindowRect(h, out r); return new int[]{ r.L, r.T, r.R, r.B }; }
  public static bool Topmost(IntPtr h){ return ((long)GetWindowLongPtr(h, -20) & 0x8) != 0; }
  public static void Click(int x, int y){
    SetCursorPos(x, y);
    System.Threading.Thread.Sleep(120);
    mouse_event(0x0002,0,0,0,IntPtr.Zero);
    System.Threading.Thread.Sleep(60);
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
[PinOut]::AltG()
Start-Sleep -Milliseconds 1500
$h = [PinOut]::Find([uint32]$p.Id, 'STranslate')
if ($h -eq [IntPtr]::Zero) { Write-Output 'MAIN: missing'; exit 1 }
[void][PinOut]::ShowWindow($h, 5)
Start-Sleep -Milliseconds 400
[void][PinOut]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 900

$r = [PinOut]::Rect($h)
Write-Output ("RECT: {0},{1} {2}x{3}" -f $r[0], $r[1], ($r[2]-$r[0]), ($r[3]-$r[1]))
Write-Output ("VISIBLE(before): {0}  TOPMOST(before): {1}" -f [PinOut]::IsWindowVisible($h), [PinOut]::Topmost($h))

# 点击左上角钉子（窗口内相对 22,18）
[PinOut]::Click(($r[0] + 22), ($r[1] + 18))
Start-Sleep -Milliseconds 900
Write-Output ("VISIBLE(after pin): {0}  TOPMOST(after pin): {1}" -f [PinOut]::IsWindowVisible($h), [PinOut]::Topmost($h))

# 点击窗口外空白处
$outX = [Math]::Min($r[2] + 300, 1870)
$outY = [Math]::Min($r[3] + 200, 1040)
Write-Output ("CLICK OUTSIDE AT: {0},{1}" -f $outX, $outY)
[PinOut]::Click($outX, $outY)
Start-Sleep -Milliseconds 1200

Write-Output ("VISIBLE(after outside click): {0}  TOPMOST: {1}" -f [PinOut]::IsWindowVisible($h), [PinOut]::Topmost($h))
