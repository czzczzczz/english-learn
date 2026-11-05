# 划词气泡实测 v3：剪贴板粘贴文本 → 鼠标拖选（更接近真实操作）→ 截图气泡 → 悬停 → 截图翻译窗口
param(
    [string]$AppDir = "D:\vibe_coding\english_learn\vendor\STranslate-main\src\.artifacts\Debug",
    [string]$OutDir = "D:\vibe_coding\english_learn\toolchain"
)

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Ui3 {
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
    $r = New-Object Ui3+RECT
    [void][Ui3]::GetWindowRect($hwnd, [ref]$r)
    $w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
    if ($w -le 0 -or $h -le 0) { Write-Host "invalid window size"; return }
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc()
    $ok = [Ui3]::PrintWindow($hwnd, $hdc, 2)
    $g.ReleaseHdc($hdc); $g.Dispose()
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    Write-Host "window ${w}x${h} printWindow=$ok -> $path"
}

$app = Get-Process STranslate -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $app) {
    $env:TMP = 'D:\vibe_coding\english_learn\toolchain\tmp'
    $env:TEMP = $env:TMP
    Start-Process -FilePath (Join-Path $AppDir "STranslate.exe") -WorkingDirectory $AppDir
    Start-Sleep -Seconds 8
    Write-Host "app launched"
} else { Write-Host "app running: $($app.Id)" }

# 记事本固定位置
$np = Start-Process "C:\Windows\System32\notepad.exe" -PassThru
Start-Sleep -Seconds 2
[void][Ui3]::SetWindowPos($np.MainWindowHandle, [IntPtr]::Zero, 120, 120, 1000, 380, 0x0040)
Start-Sleep -Milliseconds 400
[void][Ui3]::SetForegroundWindow($np.MainWindowHandle)
Start-Sleep -Milliseconds 700

# 用剪贴板粘贴，避免 SendKeys 丢字符
Set-Clipboard -Value "hello world, this is a bubble translation test."
(New-Object -ComObject WScript.Shell).SendKeys("^v")
Start-Sleep -Milliseconds 900

$pt = New-Object Ui3+POINT
[void][Ui3]::ClientToScreen($np.MainWindowHandle, [ref]$pt)
$startX = $pt.X + 45
$y = $pt.Y + 22

# 先把鼠标放到文本上小幅移动，让钩子识别到 I 型光标
[void][Ui3]::SetCursorPos($startX, $y)
Start-Sleep -Milliseconds 300
[void][Ui3]::SetCursorPos(($startX + 6), $y)
Start-Sleep -Milliseconds 700

# 拖动选中 "hello"：用鼠标相对移动（SetCursorPos 不会触发低级鼠标钩子的移动事件）
[Ui3]::mouse_event([Ui3]::LEFTDOWN, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 60
for ($i = 1; $i -le 6; $i++) {
    [Ui3]::mouse_event(0x0001, 8, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 45
}
[Ui3]::mouse_event([Ui3]::LEFTUP, 0, 0, 0, [IntPtr]::Zero)

# 气泡应出现在松开位置右下
Start-Sleep -Milliseconds 700
Save-Screen (Join-Path $OutDir "t3_1_bubble.png")

# 悬停到气泡上
[void][Ui3]::SetCursorPos(($startX + 54 + 30), ($y + 34))
Start-Sleep -Seconds 3
Save-Screen (Join-Path $OutDir "t3_2_hover.png")

$app = Get-Process STranslate -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if ($app) { Save-Window $app.MainWindowHandle (Join-Path $OutDir "t3_3_window.png") } else { Write-Host "app window not found" }

Write-Host "=== 日志尾部"
$log = Get-ChildItem (Join-Path $AppDir "PortableConfig\Logs") -Recurse -Filter *.log | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Get-Content $log.FullName -Tail 12
