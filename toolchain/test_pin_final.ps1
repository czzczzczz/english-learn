# 收尾验证：①贴顶不再吸附 ②未钉时点外部仍会隐藏
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class FinalCheck {
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
$h = [FinalCheck]::Find([uint32]$p.Id, 'STranslate')

function Show-Main {
    [FinalCheck]::AltG()
    Start-Sleep -Milliseconds 1100
    [void][FinalCheck]::ShowWindow($h, 5)
    Start-Sleep -Milliseconds 300
    [void][FinalCheck]::SetForegroundWindow($h)
    Start-Sleep -Milliseconds 600
}

# --- 测试 A：贴顶不再吸附 ---
Show-Main
if ([FinalCheck]::Topmost($h)) { [FinalCheck]::CtrlShiftT(); Start-Sleep -Milliseconds 700 }
$r = [FinalCheck]::Rect($h)
$w = $r[2] - $r[0]; $ht = $r[3] - $r[1]
[void][FinalCheck]::SetWindowPos($h, [IntPtr]::Zero, $r[0], 0, $w, $ht, 0x0040)
Start-Sleep -Milliseconds 2600
$r2 = [FinalCheck]::Rect($h)
$h2 = $r2[3] - $r2[1]
Write-Output ("A. 贴顶后: top={0} height={1} (原 {2})  => {3}" -f $r2[1], $h2, $ht, $(if ($h2 -ge ($ht - 20)) { '未吸附（正确）' } else { '被收缩（错误）' }))

# --- 测试 B：未钉时点外部应隐藏 ---
Show-Main
if ([FinalCheck]::Topmost($h)) { [FinalCheck]::CtrlShiftT(); Start-Sleep -Milliseconds 700 }
$r = [FinalCheck]::Rect($h)
$outX = 1460
$outY = [Math]::Min($r[3] + 120, 900)
Write-Output ("B. 点外部坐标 {0},{1}  topmost(click前)={2}" -f $outX, $outY, [FinalCheck]::Topmost($h))
[FinalCheck]::SetCursorPos($outX, $outY)
Start-Sleep -Milliseconds 200
[FinalCheck]::mouse_event(0x0002,0,0,0,[IntPtr]::Zero)
Start-Sleep -Milliseconds 80
for ($k = 0; $k -lt 5; $k++) { [FinalCheck]::mouse_event(0x0001,6,0,0,[IntPtr]::Zero); Start-Sleep -Milliseconds 30 }
[FinalCheck]::mouse_event(0x0004,0,0,0,[IntPtr]::Zero)
Start-Sleep -Milliseconds 1400
$vis = [FinalCheck]::IsWindowVisible($h)
Write-Output ("B. 未钉拖选外部: visible={0}  => {1}" -f $vis, $(if ($vis) { '仍显示（不符合预期）' } else { '已隐藏（正确）' }))

# --- 测试 C：钉住时点外部保持 ---
Show-Main
if (-not [FinalCheck]::Topmost($h)) { [FinalCheck]::CtrlShiftT(); Start-Sleep -Milliseconds 700 }
$r = [FinalCheck]::Rect($h)
$outX = [Math]::Max(20, $r[0] - 250)
$outY = $r[1] + 120
[FinalCheck]::Click($outX, $outY)
Start-Sleep -Milliseconds 1200
$vis = [FinalCheck]::IsWindowVisible($h)
$top = [FinalCheck]::Topmost($h)
Write-Output ("C. 钉住点外部: visible={0} topmost={1}  => {2}" -f $vis, $top, $(if ($vis -and $top) { '保持显示且置顶（正确）' } else { '不符合预期' }))
