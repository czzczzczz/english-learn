# 验证钉子置顶：点击主窗口左上角钉子，检查 WS_EX_TOPMOST 位
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class TopTest {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
    [DllImport("user32.dll")] public static extern IntPtr GetWindowLongPtr(IntPtr h, int i);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    public const uint LD = 0x0002, LU = 0x0004;
    public const int GWL_EXSTYLE = -20;
    public const int WS_EX_TOPMOST = 0x00000008;
    public static bool IsTopmost(IntPtr h) => ((long)GetWindowLongPtr(h, GWL_EXSTYLE) & WS_EX_TOPMOST) != 0;
    public static void Click(int x, int y) {
        SetCursorPos(x, y);
        System.Threading.Thread.Sleep(120);
        mouse_event(LD, 0, 0, 0, IntPtr.Zero);
        mouse_event(LU, 0, 0, 0, IntPtr.Zero);
    }
}
"@
$p = Get-Process STranslate | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { Write-Host "no window"; exit }
$h = $p.MainWindowHandle
$r = New-Object TopTest+RECT
[void][TopTest]::GetWindowRect($h, [ref]$r)
$w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
Write-Host "window rect=$($r.Left),$($r.Top) size=${w}x${ht} topmostBefore=$([TopTest]::IsTopmost($h))"

# 钉子按钮位于左上角，按窗口宽度自适应偏移
$pinX = $r.Left + 32
$pinY = $r.Top + 26
Write-Host "click pin at $pinX,$pinY"
[TopTest]::Click($pinX, $pinY)
Start-Sleep -Milliseconds 600
Write-Host "topmostAfterClick=$([TopTest]::IsTopmost($h))"

[TopTest]::Click($pinX, $pinY)
Start-Sleep -Milliseconds 600
Write-Host "topmostAfterSecondClick=$([TopTest]::IsTopmost($h))"
