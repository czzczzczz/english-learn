# 两轮对比：未钉住 / 钉住 时点击窗口外的窗口可见性
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class PinCase {
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
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint flags);
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
}
"@

$p = Get-Process STranslate
$h = [PinCase]::Find([uint32]$p.Id, 'STranslate')
if ($h -eq [IntPtr]::Zero) { Write-Output 'MAIN: missing'; exit 1 }

function Show-Main {
    [PinCase]::AltG()
    Start-Sleep -Milliseconds 1300
    [void][PinCase]::ShowWindow($h, 5)
    Start-Sleep -Milliseconds 300
    [void][PinCase]::SetForegroundWindow($h)
    Start-Sleep -Milliseconds 800
}

function Get-State($tag) {
    $r = [PinCase]::Rect($h)
    Write-Host ("[{0}] rect={1},{2} {3}x{4} visible={5} topmost={6}" -f $tag, $r[0], $r[1], ($r[2]-$r[0]), ($r[3]-$r[1]), [PinCase]::IsWindowVisible($h), [PinCase]::Topmost($h))
    return $r
}

# 轮 1：不管当前状态，直接点外部 → 记录行为
Show-Main
$r = Get-State 'round1-before'
[PinCase]::Click(($r[0] + 120), ($r[3] + 160))
Start-Sleep -Milliseconds 1500
$vis1 = [PinCase]::IsWindowVisible($h)
Write-Output ("ROUND1 (click outside): visible={0}" -f $vis1)

# 轮 2：确保钉住后再点外部
Show-Main
$r = Get-State 'round2-before'
if (-not [PinCase]::Topmost($h)) {
    Write-Output 'round2: window not topmost, clicking pin to pin it'
    [PinCase]::Click(($r[0] + 22), ($r[1] + 18))
    Start-Sleep -Milliseconds 800
}
$r = Get-State 'round2-pinned'
[PinCase]::Click(($r[0] + 120), ($r[3] + 160))
Start-Sleep -Milliseconds 1500
$vis2 = [PinCase]::IsWindowVisible($h)
Write-Output ("ROUND2 (pinned, click outside): visible={0}" -f $vis2)

if ($vis2) { Write-Output 'VERDICT: 置顶时点击外部不隐藏（正常）' } else { Write-Output 'VERDICT: 置顶时点击外部仍隐藏（BUG 复现）' }
