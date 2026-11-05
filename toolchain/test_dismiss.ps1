# 验证 v6：气泡悬停弹出翻译窗口后，点击别处窗口应立即消失
param(
    [string]$AppDir = "D:\vibe_coding\STranslate-dev",
    [string]$OutDir = "D:\vibe_coding\english_learn\toolchain"
)

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Ui6 {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, IntPtr extra);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hWnd, ref POINT point);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
    public const uint LEFTDOWN = 0x0002, LEFTUP = 0x0004;
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
    [void][Ui6]::SetCursorPos($x, $y)
    Start-Sleep -Milliseconds 400
    [void][Ui6]::SetCursorPos(($x + 3), $y)
    Start-Sleep -Milliseconds 500
    [Ui6]::mouse_event([Ui6]::LEFTDOWN, 0, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    for ($i = 1; $i -le 6; $i++) {
        [Ui6]::mouse_event(0x0001, [int]($dx / 6), 0, 0, [IntPtr]::Zero)
        Start-Sleep -Milliseconds 45
    }
    [Ui6]::mouse_event([Ui6]::LEFTUP, 0, 0, 0, [IntPtr]::Zero)
}

if (-not (Get-Process STranslate -ErrorAction SilentlyContinue)) {
    Start-Process -FilePath (Join-Path $AppDir "STranslate.exe") -WorkingDirectory $AppDir
    Start-Sleep -Seconds 8
    Write-Host "app launched"
}

$np = Start-Process "C:\Windows\System32\notepad.exe" -PassThru
Start-Sleep -Seconds 2
[void][Ui6]::SetWindowPos($np.MainWindowHandle, [IntPtr]::Zero, 120, 120, 1000, 380, 0x0040)
Start-Sleep -Milliseconds 400
[void][Ui6]::SetForegroundWindow($np.MainWindowHandle)
Start-Sleep -Milliseconds 600
Set-Clipboard -Value "hello world this is a translation window test"
(New-Object -ComObject WScript.Shell).SendKeys("^v")
Start-Sleep -Milliseconds 800

$pt = New-Object Ui6+POINT
[void][Ui6]::ClientToScreen($np.MainWindowHandle, [ref]$pt)
$x = $pt.X + 45
$y = $pt.Y + 22

# 拖选 → 悬停 → 翻译窗口
Drag-Select $x $y 60
Start-Sleep -Milliseconds 600
[void][Ui6]::SetCursorPos(($x + 60 + 28), ($y + 32))
Start-Sleep -Seconds 2
Save-Screen (Join-Path $OutDir "v6_1_window.png")

# 点击记事本空白处 → 窗口应消失
[void][Ui6]::SetCursorPos(($pt.X + 300), ($pt.Y + 250))
Start-Sleep -Milliseconds 200
[Ui6]::mouse_event([Ui6]::LEFTDOWN, 0, 0, 0, [IntPtr]::Zero)
[Ui6]::mouse_event([Ui6]::LEFTUP, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 900
Save-Screen (Join-Path $OutDir "v6_2_after_click.png")

$win = Get-Process STranslate -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if ($win) { Write-Host "main window handle exists: $($win.MainWindowHandle)" } else { Write-Host "main window hidden (handle 0)" }
