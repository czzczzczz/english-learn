# 划词气泡实测：启动应用 → 记事本输入文本 → 双击选词 → 等待气泡 → 悬停 → 截图
param(
    [string]$AppDir = "D:\vibe_coding\english_learn\vendor\STranslate-main\src\.artifacts\Debug",
    [string]$OutDir = "D:\vibe_coding\english_learn\toolchain"
)

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Ui {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, IntPtr extra);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hWnd, ref POINT point);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);
    public const uint LEFTDOWN = 0x0002, LEFTUP = 0x0004;
}
"@

function Save-Screen([string]$path) {
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
    $g.Dispose()
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host "screen -> $path"
}

function Save-Window([string]$procName, [string]$path) {
    $p = Get-Process -Name $procName -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if (-not $p) { Write-Host "no window for $procName"; return $false }
    $r = New-Object Ui+RECT
    [void][Ui]::GetWindowRect($p.MainWindowHandle, [ref]$r)
    $w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc()
    $ok = [Ui]::PrintWindow($p.MainWindowHandle, $hdc, 2)
    $g.ReleaseHdc($hdc); $g.Dispose()
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host "window $procName ${w}x${h} printWindow=$ok -> $path"
    return $true
}

function Invoke-DoubleClick([int]$x, [int]$y) {
    [void][Ui]::SetCursorPos($x, $y)
    Start-Sleep -Milliseconds 200
    [Ui]::mouse_event([Ui]::LEFTDOWN, 0, 0, 0, [IntPtr]::Zero)
    [Ui]::mouse_event([Ui]::LEFTUP, 0, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    [Ui]::mouse_event([Ui]::LEFTDOWN, 0, 0, 0, [IntPtr]::Zero)
    [Ui]::mouse_event([Ui]::LEFTUP, 0, 0, 0, [IntPtr]::Zero)
}

# 1. 启动应用
Get-Process -Name STranslate -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1
Start-Process -FilePath (Join-Path $AppDir "STranslate.exe") -WorkingDirectory $AppDir
Start-Sleep -Seconds 7
Write-Host "app started: $((Get-Process -Name STranslate -ErrorAction SilentlyContinue | Measure-Object).Count) process(es)"

# 2. 启动记事本并输入英文
$np = Start-Process notepad -PassThru
Start-Sleep -Seconds 2
[void][Ui]::SetForegroundWindow($np.MainWindowHandle)
Start-Sleep -Milliseconds 500
(New-Object -ComObject WScript.Shell).SendKeys("translation bubble hover test")
Start-Sleep -Milliseconds 800

# 3. 在文本区域双击选中一个单词
$r = New-Object Ui+RECT
[void][Ui]::GetWindowRect($np.MainWindowHandle, [ref]$r)
$pt = New-Object Ui+POINT
$pt.X = 0; $pt.Y = 0
[void][Ui]::ClientToScreen($np.MainWindowHandle, [ref]$pt)
$clickX = $pt.X + 45
$clickY = $pt.Y + 22
Write-Host "notepad rect=$($r.Left),$($r.Top),$($r.Right),$($r.Bottom) click=$clickX,$clickY"
Invoke-DoubleClick $clickX $clickY

# 4. 等气泡出现并截图
Start-Sleep -Milliseconds 900
Save-Screen (Join-Path $OutDir "bubble1_selected.png")

# 5. 把鼠标移到气泡位置（气泡默认在光标 +12,+12），等待悬停翻译
[void][Ui]::SetCursorPos(($clickX + 24), ($clickY + 24))
Start-Sleep -Seconds 2
Save-Screen (Join-Path $OutDir "bubble2_hover.png")
[void](Save-Window "STranslate" (Join-Path $OutDir "bubble3_window.png"))

# 6. 输出应用日志尾部
$logDir = Join-Path $AppDir "PortableConfig\Logs"
if (Test-Path $logDir) {
    Get-ChildItem $logDir -Recurse -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | ForEach-Object {
        Write-Host "=== log: $($_.FullName)"
        Get-Content $_.FullName -Tail 25
    }
}
