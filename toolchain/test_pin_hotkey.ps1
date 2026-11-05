# 用热键 Ctrl+Shift+T 切换置顶，核对 WS_EX_TOPMOST；再从窗口左侧外部点击验证是否消失
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class PinHot {
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
    System.Threading.Thread.Sleep(130);
    mouse_event(0x0002,0,0,0,IntPtr.Zero);
    System.Threading.Thread.Sleep(70);
    mouse_event(0x0004,0,0,0,IntPtr.Zero);
  }
  public static void AltG(){
    keybd_event(0x12,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x47,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x47,0,2,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x12,0,2,IntPtr.Zero);
  }
  public static void CtrlShiftT(){
    keybd_event(0x11,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(50);
    keybd_event(0x10,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(50);
    keybd_event(0x54,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(50);
    keybd_event(0x54,0,2,IntPtr.Zero); System.Threading.Thread.Sleep(50);
    keybd_event(0x10,0,2,IntPtr.Zero); System.Threading.Thread.Sleep(50);
    keybd_event(0x11,0,2,IntPtr.Zero);
  }
}
"@

$p = Get-Process STranslate
$h = [PinHot]::Find([uint32]$p.Id, 'STranslate')
if ($h -eq [IntPtr]::Zero) { Write-Output 'MAIN: missing'; exit 1 }

[PinHot]::AltG()
Start-Sleep -Milliseconds 1200
[void][PinHot]::ShowWindow($h, 5)
Start-Sleep -Milliseconds 300
[void][PinHot]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 800

$r = [PinHot]::Rect($h)
Write-Output ("window rect: {0},{1} {2}x{3}  visible={4} topmost={5}" -f $r[0], $r[1], ($r[2]-$r[0]), ($r[3]-$r[1]), [PinHot]::IsWindowVisible($h), [PinHot]::Topmost($h))

# 热键钉住
[PinHot]::CtrlShiftT()
Start-Sleep -Milliseconds 800
Write-Output ("after Ctrl+Shift+T: topmost={0}" -f [PinHot]::Topmost($h))

$outX = [Math]::Max(20, $r[0] - 200)
$outY = $r[1] + 120
Write-Output ("click outside at: {0},{1}" -f $outX, $outY)
[PinHot]::Click($outX, $outY)
Start-Sleep -Milliseconds 1200
Write-Output ("after outside click (pinned): visible={0} topmost={1}" -f [PinHot]::IsWindowVisible($h), [PinHot]::Topmost($h))

# 热键取消钉住
if (-not [PinHot]::IsWindowVisible($h)) {
    [PinHot]::AltG()
    Start-Sleep -Milliseconds 1000
}
[PinHot]::CtrlShiftT()
Start-Sleep -Milliseconds 800
Write-Output ("after Ctrl+Shift+T (unpin): topmost={0} visible={1}" -f [PinHot]::Topmost($h), [PinHot]::IsWindowVisible($h))
