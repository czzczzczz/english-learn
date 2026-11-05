# 钉住状态机实测：反复切换 5 次，核对 WS_EX_TOPMOST / 可见性 / 点外部行为
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class PinCheck {
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
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint flags);
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
$h = [PinCheck]::Find([uint32]$p.Id, 'STranslate')
if ($h -eq [IntPtr]::Zero) { Write-Output 'MAIN: missing'; exit 1 }

function Show-Main {
    [PinCheck]::AltG()
    Start-Sleep -Milliseconds 1200
    [void][PinCheck]::ShowWindow($h, 5)
    Start-Sleep -Milliseconds 300
    [void][PinCheck]::SetForegroundWindow($h)
    Start-Sleep -Milliseconds 700
}

Show-Main
$r = [PinCheck]::Rect($h)
Write-Output ("start: visible={0} topmost={1} rect={2},{3}" -f [PinCheck]::IsWindowVisible($h), [PinCheck]::Topmost($h), $r[0], $r[1])

# 确认起始为未钉（若已钉先点掉）
if ([PinCheck]::Topmost($h)) {
    [PinCheck]::Click(($r[0] + 22), ($r[1] + 18))
    Start-Sleep -Milliseconds 700
    Write-Output ("normalized to unpinned: topmost={0}" -f [PinCheck]::Topmost($h))
}

$fail = 0
for ($i = 1; $i -le 5; $i++) {
    # 钉住
    $r = [PinCheck]::Rect($h)
    [PinCheck]::Click(($r[0] + 22), ($r[1] + 18))
    Start-Sleep -Milliseconds 600
    $tOn = [PinCheck]::Topmost($h)
    # 钉住状态点窗口外
    [PinCheck]::Click(($r[0] + 120), ($r[3] + 150))
    Start-Sleep -Milliseconds 900
    $vOn = [PinCheck]::IsWindowVisible($h)
    Write-Output ("round {0} PIN  -> topmost={1} visibleAfterOutsideClick={2}" -f $i, $tOn, $vOn)
    if (-not $tOn) { $fail++ }
    if (-not $vOn) { $fail++; Show-Main }

    # 取消钉住
    $r = [PinCheck]::Rect($h)
    [PinCheck]::Click(($r[0] + 22), ($r[1] + 18))
    Start-Sleep -Milliseconds 600
    $tOff = [PinCheck]::Topmost($h)
    Write-Output ("round {0} UNPIN-> topmost={1}" -f $i, $tOff)
    if ($tOff) { $fail++ }

    if (-not [PinCheck]::IsWindowVisible($h)) { Show-Main }
}

Write-Output ("FAILURES: {0}" -f $fail)
if ($fail -eq 0) { Write-Output 'VERDICT: 钉住/取消 5 轮全部与钉子状态一致' } else { Write-Output 'VERDICT: 仍有不一致' }
