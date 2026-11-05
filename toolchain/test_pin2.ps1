# 找到标题为 STranslate 的窗口，点击左上角钉子，检查 WS_EX_TOPMOST
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class PinTest {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern long GetWindowLongPtr(IntPtr h, int i);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint d1, uint d2, uint d3, IntPtr e);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    public const uint LD = 0x0002, LU = 0x0004;
    public static IntPtr FindByTitle(uint pid, string title) {
        IntPtr found = IntPtr.Zero;
        EnumWindows((h, l) => {
            uint p; GetWindowThreadProcessId(h, out p);
            if (p == pid) {
                var sb = new StringBuilder(256);
                GetWindowText(h, sb, 256);
                if (sb.ToString() == title) { found = h; return false; }
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }
    public static bool IsTopmost(IntPtr h) => ((long)GetWindowLongPtr(h, -20) & 0x8) != 0;
    public static void Click(int x, int y) {
        SetCursorPos(x, y);
        System.Threading.Thread.Sleep(150);
        mouse_event(LD, 0, 0, 0, IntPtr.Zero);
        mouse_event(LU, 0, 0, 0, IntPtr.Zero);
    }
}
"@
$p = Get-Process STranslate
$h = [PinTest]::FindByTitle([uint32]$p.Id, "STranslate")
if ($h -eq [IntPtr]::Zero) { Write-Host "window not found"; exit }
$r = New-Object PinTest+RECT
[void][PinTest]::GetWindowRect($h, [ref]$r)
Write-Host "hwnd=$h rect=$($r.Left),$($r.Top),$($r.Right),$($r.Bottom) topmostBefore=$([PinTest]::IsTopmost($h))"
$pinX = $r.Left + 32
$pinY = $r.Top + 26
[PinTest]::Click($pinX, $pinY)
Start-Sleep -Milliseconds 700
Write-Host "afterFirstClick=$([PinTest]::IsTopmost($h))"
[PinTest]::Click($pinX, $pinY)
Start-Sleep -Milliseconds 700
Write-Host "afterSecondClick=$([PinTest]::IsTopmost($h))"
