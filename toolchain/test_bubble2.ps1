# 划词气泡实测 v2：确保应用运行 → 记事本输入文本 → 双击选词 → 截图气泡 → 悬停 → 截图翻译窗口
param(
    [string]$AppDir = "D:\vibe_coding\english_learn\vendor\STranslate-main\src\.artifacts\Debug",
    [string]$OutDir = "D:\vibe_coding\english_learn\toolchain"
)

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Ui2 {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, IntPtr extra);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hWnd, ref POINT point);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);
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

function Save-Window([IntPtr]$hwnd, [string]$path) {
    $r = New-Object Ui2+RECT
    [void][Ui2]::GetWindowRect($hwnd, [ref]$r)
    $w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
    if ($w -le 0 -or $h -le 0) { Write-Host "invalid window size"; return }
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc()
    $ok = [Ui2]::PrintWindow($hwnd, $hdc, 2)
    $g.ReleaseHdc($hdc); $g.Dispose()
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    Write-Host "window ${w}x${h} printWindow=$ok -> $path"
}

# 1. 确保应用在跑
$app = Get-Process STranslate -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $app) {
    $env:TMP = 'D:\vibe_coding\english_learn\toolchain\tmp'
    $env:TEMP = $env:TMP
    Start-Process -FilePath (Join-Path $AppDir "STranslate.exe") -WorkingDirectory $AppDir
    Start-Sleep -Seconds 8
    Write-Host "app launched"
}
else { Write-Host "app already running: $($app.Id)" }

# 2. 记事本：固定位置 + 输入文本
$np = Start-Process "C:\Windows\System32\notepad.exe" -PassThru
Start-Sleep -Seconds 2
[void][Ui2]::SetWindowPos($np.MainWindowHandle, [IntPtr]::Zero, 120, 120, 900, 360, 0x0040)
Start-Sleep -Milliseconds 400
[void][Ui2]::SetForegroundWindow($np.MainWindowHandle)
Start-Sleep -Milliseconds 600
(New-Object -ComObject WScript.Shell).SendKeys("hello world, this is a bubble translation test.")
Start-Sleep -Milliseconds 600

# 3. 双击选中 "world"
$pt = New-Object Ui2+POINT
[void][Ui2]::ClientToScreen($np.MainWindowHandle, [ref]$pt)
$clickX = $pt.X + 105
$clickY = $pt.Y + 22
Write-Host "client origin=$($pt.X),$($pt.Y) click=$clickX,$clickY"
[void][Ui2]::SetCursorPos($clickX, $clickY)
Start-Sleep -Milliseconds 250
[Ui2]::mouse_event([Ui2]::LEFTDOWN, 0, 0, 0, [IntPtr]::Zero)
[Ui2]::mouse_event([Ui2]::LEFTUP, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 70
[Ui2]::mouse_event([Ui2]::LEFTDOWN, 0, 0, 0, [IntPtr]::Zero)
[Ui2]::mouse_event([Ui2]::LEFTUP, 0, 0, 0, [IntPtr]::Zero)

# 4. 等气泡出现（气泡在光标右下 12px 起）
Start-Sleep -Milliseconds 800
Save-Screen (Join-Path $OutDir "t2_1_after_select.png")

# 5. 悬停到气泡上（气泡 44x44，中心约 +12+22）
[void][Ui2]::SetCursorPos(($clickX + 30), ($clickY + 34))
Start-Sleep -Seconds 3
Save-Screen (Join-Path $OutDir "t2_2_after_hover.png")

# 6. 打印应用窗口
$app = Get-Process STranslate -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if ($app) { Save-Window $app.MainWindowHandle (Join-Path $OutDir "t2_3_app_window.png") }
else { Write-Host "app window handle not found" }
Write-Host "done"
