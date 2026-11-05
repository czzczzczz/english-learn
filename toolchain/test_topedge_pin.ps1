# 复现：窗口贴顶 + 置顶 + 点击窗口外，是否被顶边自动收起
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class TopEdge {
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
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
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
  public static void Move(int x, int y, int w, int h){ SetWindowPos(FindByTitleCurrent, IntPtr.Zero, 0,0,0,0, 0); }
  public static IntPtr FindByTitleCurrent = IntPtr.Zero;
  public static void AltG(){
    keybd_event(0x12,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x47,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x47,0,2,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x12,0,2,IntPtr.Zero);
  }
}
"@

$p = Get-Process STranslate
[TopEdge]::AltG()
Start-Sleep -Milliseconds 1500
$h = [TopEdge]::Find([uint32]$p.Id, 'STranslate')
if ($h -eq [IntPtr]::Zero) { Write-Output 'MAIN: missing'; exit 1 }
[void][TopEdge]::ShowWindow($h, 5)
Start-Sleep -Milliseconds 500
[void][TopEdge]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 800

$r = [TopEdge]::Rect($h)
$w = $r[2] - $r[0]; $ht = $r[3] - $r[1]
Write-Output ("BEFORE MOVE: {0},{1} {2}x{3} visible={4} topmost={5}" -f $r[0], $r[1], $w, $ht, [TopEdge]::IsWindowVisible($h), [TopEdge]::Topmost($h))

# 贴到屏幕顶边（y=0）
[void][TopEdge]::SetWindowPos($h, [IntPtr]::Zero, $r[0], 0, $w, $ht, 0x0040)
Start-Sleep -Milliseconds 1600
$r = [TopEdge]::Rect($h)
Write-Output ("AFTER MOVE TO TOP: {0},{1} {2}x{3} topmost={4}" -f $r[0], $r[1], ($r[2]-$r[0]), ($r[3]-$r[1]), [TopEdge]::Topmost($h))

# 点钉子（窗口内 22,18）
[TopEdge]::Click(($r[0] + 22), ($r[1] + 18))
Start-Sleep -Milliseconds 800
Write-Output ("AFTER PIN: topmost={0}" -f [TopEdge]::Topmost($h))

# 点窗口外下方
[TopEdge]::Click(($r[0] + 120), ($r[3] + 180))
Start-Sleep -Milliseconds 1800

$r2 = [TopEdge]::Rect($h)
Write-Output ("AFTER OUTSIDE CLICK: {0},{1} {2}x{3} visible={4} topmost={5}" -f $r2[0], $r2[1], ($r2[2]-$r2[0]), ($r2[3]-$r2[1]), [TopEdge]::IsWindowVisible($h), [TopEdge]::Topmost($h))
if (($r2[3] - $r2[1]) -lt 40) { Write-Output 'RESULT: 窗口被顶边收起（复现）' } else { Write-Output 'RESULT: 窗口保持展开' }
