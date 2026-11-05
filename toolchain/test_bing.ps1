# 验证必应词典插件：选中单词 → 气泡 → 悬停 → 翻译窗口显示音标/释义
param(
    [string]$AppDir = "D:\vibe_coding\STranslate-dev",
    [string]$OutDir = "D:\vibe_coding\english_learn\toolchain"
)
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class U8 {
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
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
        AttachThreadInput(cur, fg, true);
        SetForegroundWindow(h);
        AttachThreadInput(cur, fg, false);
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
[void][U8]::SetWindowPos($np.MainWindowHandle, [IntPtr]::Zero, 120, 120, 900, 300, 0x0040)
[U8]::Force($np.MainWindowHandle)
Start-Sleep -Milliseconds 700
Set-Clipboard -Value "salad"
(New-Object -ComObject WScript.Shell).SendKeys("^v")
Start-Sleep -Milliseconds 900
$pt = New-Object U8+POINT
[void][U8]::ClientToScreen($np.MainWindowHandle, [ref]$pt)
$x = $pt.X + 20; $y = $pt.Y + 20
[void][U8]::SetCursorPos($x, $y); Start-Sleep -Milliseconds 400
[void][U8]::SetCursorPos(($x + 3), $y); Start-Sleep -Milliseconds 500
# 双击选中单词
[U8]::mouse_event([U8]::LD, 0, 0, 0, [IntPtr]::Zero); [U8]::mouse_event([U8]::LU, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 80
[U8]::mouse_event([U8]::LD, 0, 0, 0, [IntPtr]::Zero); [U8]::mouse_event([U8]::LU, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 900
Save-Screen (Join-Path $OutDir "v8_1_bubble.png")
[void][U8]::SetCursorPos(($x + 30), ($y + 34))
Start-Sleep -Seconds 8
Save-Screen (Join-Path $OutDir "v8_2_result.png")
$log = Get-ChildItem (Join-Path $AppDir "PortableConfig\Logs") -Recurse -Filter *.log | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Write-Host "=== 日志尾部"
Get-Content $log.FullName -Tail 10
