# 验证 v7：气泡翻译窗口是否浮在最上层，以及点击别处是否隐藏
param(
    [string]$AppDir = "D:\vibe_coding\STranslate-dev",
    [string]$OutDir = "D:\vibe_coding\english_learn\toolchain"
)

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Ui7 {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, IntPtr extra);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hWnd, ref POINT point);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int cmd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, IntPtr pid);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
    public const uint LEFTDOWN = 0x0002, LEFTUP = 0x0004;
    public static void ForceForeground(IntPtr hWnd) {
        ShowWindow(hWnd, 9);
        uint fg = GetWindowThreadProcessId(GetForegroundWindow(), IntPtr.Zero);
        uint cur = GetCurrentThreadId();
        AttachThreadInput(cur, fg, true);
        SetForegroundWindow(hWnd);
        AttachThreadInput(cur, fg, false);
    }
}
"@

function Save-Screen([string]$path) {
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
    $g.Dispose(); $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    Write-Host "screen -> $path"
}

function Drag-Select([int]$x, [int]$y, [int]$dx) {
    [void][Ui7]::SetCursorPos($x, $y)
    Start-Sleep -Milliseconds 400
    [void][Ui7]::SetCursorPos(($x + 3), $y)
    Start-Sleep -Milliseconds 400
    [Ui7]::mouse_event([Ui7]::LEFTDOWN, 0, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    for ($i = 1; $i -le 6; $i++) {
        [Ui7]::mouse_event(0x0001, [int]($dx / 6), 0, 0, [IntPtr]::Zero)
        Start-Sleep -Milliseconds 45
    }
    [Ui7]::mouse_event([Ui7]::LEFTUP, 0, 0, 0, [IntPtr]::Zero)
}

if (-not (Get-Process STranslate -ErrorAction SilentlyContinue)) {
    Start-Process -FilePath (Join-Path $AppDir "STranslate.exe") -WorkingDirectory $AppDir
    Start-Sleep -Seconds 8
    Write-Host "app launched"
}

$np = Start-Process "C:\Windows\System32\notepad.exe" -PassThru
Start-Sleep -Seconds 2
[void][Ui7]::SetWindowPos($np.MainWindowHandle, [IntPtr]::Zero, 120, 120, 1000, 380, 0x0040)
Start-Sleep -Milliseconds 300
[Ui7]::ForceForeground($np.MainWindowHandle)
Start-Sleep -Milliseconds 800
$fg = [Ui7]::GetForegroundWindow()
Write-Host "notepad hwnd=$($np.MainWindowHandle) foreground=$fg match=$($fg -eq $np.MainWindowHandle)"

(New-Object -ComObject WScript.Shell).SendKeys("^v")
Start-Sleep -Milliseconds 800
Set-Clipboard -Value $null
Start-Sleep -Milliseconds 200
Set-Clipboard -Value "hello world this is a translation window test"
(New-Object -ComObject WScript.Shell).SendKeys("^v")
Start-Sleep -Milliseconds 900

$pt = New-Object Ui7+POINT
[void][Ui7]::ClientToScreen($np.MainWindowHandle, [ref]$pt)
$x = $pt.X + 45
$y = $pt.Y + 22

Drag-Select $x $y 60
Start-Sleep -Milliseconds 700
[void][Ui7]::SetCursorPos(($x + 60 + 28), ($y + 32))
Start-Sleep -Seconds 2
Save-Screen (Join-Path $OutDir "v7_1_window.png")
$fg2 = [Ui7]::GetForegroundWindow()
Write-Host "foreground after translate = $fg2"

# 点击记事本空白处 → 窗口应消失
[void][Ui7]::SetCursorPos(($pt.X + 300), ($pt.Y + 250))
Start-Sleep -Milliseconds 200
[Ui7]::mouse_event([Ui7]::LEFTDOWN, 0, 0, 0, [IntPtr]::Zero)
[Ui7]::mouse_event([Ui7]::LEFTUP, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 900
Save-Screen (Join-Path $OutDir "v7_2_after_click.png")

$win = Get-Process STranslate -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if ($win) { Write-Host "main window still visible" } else { Write-Host "main window hidden" }
