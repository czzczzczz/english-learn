# 观察气泡存活时间：选中后 0.25s / 0.8s / 1.5s / 2.5s 各截一张
param(
    [string]$OutDir = "D:\vibe_coding\english_learn\toolchain"
)
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class U9 {
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr p);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool at);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    public const uint LD = 0x0002, LU = 0x0004;
    public static void Force(IntPtr h) {
        ShowWindow(h, 9);
        uint fg = GetWindowThreadProcessId(GetForegroundWindow(), IntPtr.Zero);
        uint cur = GetCurrentThreadId();
        AttachThreadInput(cur, fg, true); SetForegroundWindow(h); AttachThreadInput(cur, fg, false);
    }
}
"@
function Save-Screen([string]$p) {
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen(0, 0, 0, 0, $bmp.Size); $g.Dispose()
    $bmp.Save($p, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    Write-Host "screen -> $p"
}
$np = Start-Process "C:\Windows\System32\notepad.exe" -PassThru
Start-Sleep -Seconds 2
[void][U9]::SetWindowPos($np.MainWindowHandle, [IntPtr]::Zero, 150, 150, 800, 260, 0x0040)
[U9]::Force($np.MainWindowHandle)
Start-Sleep -Milliseconds 600
Set-Clipboard -Value "bubble lifetime check"
(New-Object -ComObject WScript.Shell).SendKeys("^v")
Start-Sleep -Milliseconds 800
$pt = New-Object U9+POINT
[void][U9]::ClientToScreen($np.MainWindowHandle, [ref]$pt)
$x = $pt.X + 20; $y = $pt.Y + 20
[void][U9]::SetCursorPos($x, $y); Start-Sleep -Milliseconds 400
[void][U9]::SetCursorPos(($x + 3), $y); Start-Sleep -Milliseconds 500
[U9]::mouse_event([U9]::LD, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 60
for ($i = 0; $i -lt 6; $i++) { [U9]::mouse_event(0x0001, 8, 0, 0, [IntPtr]::Zero); Start-Sleep -Milliseconds 40 }
[U9]::mouse_event([U9]::LU, 0, 0, 0, [IntPtr]::Zero)

Start-Sleep -Milliseconds 250; Save-Screen (Join-Path $OutDir "t_a_250ms.png")
Start-Sleep -Milliseconds 550; Save-Screen (Join-Path $OutDir "t_b_800ms.png")
Start-Sleep -Milliseconds 700; Save-Screen (Join-Path $OutDir "t_c_1500ms.png")
Start-Sleep -Milliseconds 1000; Save-Screen (Join-Path $OutDir "t_d_2500ms.png")

$log = Get-ChildItem "D:\vibe_coding\STranslate-dev\PortableConfig\Logs" -Recurse -Filter *.log | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Write-Host "=== 日志"
Get-Content $log.FullName -Tail 8
