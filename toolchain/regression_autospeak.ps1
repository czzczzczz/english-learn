$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

Add-Type @"
using System; using System.Runtime.InteropServices;
public class Ui5 {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, IntPtr extra);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hWnd, ref POINT point);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);
    public const uint LEFTDOWN = 0x0002, LEFTUP = 0x0004;
}
"@

function Save-Window([IntPtr]$hwnd, [string]$path) {
    $r = New-Object Ui5+RECT
    [void][Ui5]::GetWindowRect($hwnd, [ref]$r)
    $w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
    if ($w -le 0 -or $h -le 0) { Write-Output "invalid size"; return }
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc()
    $ok = [Ui5]::PrintWindow($hwnd, $hdc, 2)
    $g.ReleaseHdc($hdc); $g.Dispose()
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    Write-Output ("shot ${w}x${h} printWindow=$ok -> $path")
}

$AppDir = 'D:\vibe_coding\STranslate-dev'
$log = Get-ChildItem (Join-Path $AppDir 'PortableConfig\Logs') -Recurse -Filter *.log |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
$baseLines = (Get-Content $log.FullName).Count
Write-Output ("LOG: {0}  BASELINE LINES: {1}" -f $log.Name, $baseLines)

$app = Get-Process STranslate -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $app) { Write-Output 'APP: not running'; exit 1 }
Write-Output ("APP: PID {0}" -f $app.Id)

# 记事本
$np = Start-Process 'C:\Windows\System32\notepad.exe' -PassThru
Start-Sleep -Seconds 2
[void][Ui5]::SetWindowPos($np.MainWindowHandle, [IntPtr]::Zero, 120, 120, 1000, 380, 0x0040)
Start-Sleep -Milliseconds 400
[void][Ui5]::SetForegroundWindow($np.MainWindowHandle)
Start-Sleep -Milliseconds 700

Set-Clipboard -Value 'hello world, this is a bubble translation test.'
(New-Object -ComObject WScript.Shell).SendKeys('^v')
Start-Sleep -Milliseconds 900

$pt = New-Object Ui5+POINT
[void][Ui5]::ClientToScreen($np.MainWindowHandle, [ref]$pt)
$startX = $pt.X + 45
$y = $pt.Y + 22

[void][Ui5]::SetCursorPos($startX, $y)
Start-Sleep -Milliseconds 300
[void][Ui5]::SetCursorPos(($startX + 6), $y)
Start-Sleep -Milliseconds 700

[Ui5]::mouse_event([Ui5]::LEFTDOWN, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 60
for ($i = 1; $i -le 6; $i++) {
    [Ui5]::mouse_event(0x0001, 8, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 45
}
[Ui5]::mouse_event([Ui5]::LEFTUP, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 900

$out = 'D:\vibe_coding\english_learn\toolchain\rg1_bubble.png'
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size); $g.Dispose()
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
Write-Output ("SCREEN BUBBLE -> {0}" -f $out)

# 悬停气泡
[void][Ui5]::SetCursorPos(($startX + 54 + 30), ($y + 34))
Start-Sleep -Seconds 4

$app2 = Get-Process STranslate -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if ($app2) { Save-Window $app2.MainWindowHandle 'D:\vibe_coding\english_learn\toolchain\rg2_window.png' }

# 关闭记事本（不保存）
Stop-Process -Id $np.Id -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

Write-Output '=== 新增日志（朗读/翻译相关）'
$tail = Get-Content $log.FullName | Select-Object -Skip $baseLines
$tail | Where-Object { $_ -match 'dictvoice|translate_tts|gettts|AudioPlayer|SilentTts|AutoSpeak|翻译|Translate' } | Select-Object -First 40
Write-Output ("=== 新增日志总行数: {0}" -f $tail.Count)
