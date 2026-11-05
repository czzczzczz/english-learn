# 验证 v4：气泡随点击消失 + 悬停翻译 + 剪贴板不被污染
param(
    [string]$AppDir = "D:\vibe_coding\STranslate-dev",
    [string]$OutDir = "D:\vibe_coding\english_learn\toolchain"
)

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Ui4 {
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
    [void][Ui4]::SetCursorPos($x, $y)
    Start-Sleep -Milliseconds 400
    [void][Ui4]::SetCursorPos(($x + 3), $y)
    Start-Sleep -Milliseconds 500
    [Ui4]::mouse_event([Ui4]::LEFTDOWN, 0, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    for ($i = 1; $i -le 6; $i++) {
        [Ui4]::mouse_event(0x0001, [int]($dx / 6), 0, 0, [IntPtr]::Zero)
        Start-Sleep -Milliseconds 45
    }
    [Ui4]::mouse_event([Ui4]::LEFTUP, 0, 0, 0, [IntPtr]::Zero)
}

if (-not (Get-Process STranslate -ErrorAction SilentlyContinue)) {
    Start-Process -FilePath (Join-Path $AppDir "STranslate.exe") -WorkingDirectory $AppDir
    Start-Sleep -Seconds 8
    Write-Host "app launched"
}

$np = Start-Process "C:\Windows\System32\notepad.exe" -PassThru
Start-Sleep -Seconds 2
[void][Ui4]::SetWindowPos($np.MainWindowHandle, [IntPtr]::Zero, 120, 120, 1000, 380, 0x0040)
Start-Sleep -Milliseconds 400
[void][Ui4]::SetForegroundWindow($np.MainWindowHandle)
Start-Sleep -Milliseconds 600
Set-Clipboard -Value "CLIPBOARD-SENTINEL"
(New-Object -ComObject WScript.Shell).SendKeys("^v")
Start-Sleep -Milliseconds 800

$pt = New-Object Ui4+POINT
[void][Ui4]::ClientToScreen($np.MainWindowHandle, [ref]$pt)
$x = $pt.X + 45
$y = $pt.Y + 22

# 1. 拖选 → 气泡
Drag-Select $x $y 80
Start-Sleep -Milliseconds 700
Save-Screen (Join-Path $OutDir "v4_1_bubble.png")

# 2. 点击记事本空白处，选区消失 → 气泡应立即消失
[void][Ui4]::SetCursorPos(($pt.X + 300), ($pt.Y + 220))
Start-Sleep -Milliseconds 200
[Ui4]::mouse_event([Ui4]::LEFTDOWN, 0, 0, 0, [IntPtr]::Zero)
[Ui4]::mouse_event([Ui4]::LEFTUP, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 400
Save-Screen (Join-Path $OutDir "v4_2_after_click.png")

# 3. 剪贴板检查（应仍是 sentinel）
$clip = Get-Clipboard -Raw
Write-Host "clipboard after selection = [$($clip -replace '\s+',' ')]"

# 4. 再拖选一次 → 悬停 → 翻译窗口
Drag-Select $x $y 80
Start-Sleep -Milliseconds 700
[void][Ui4]::SetCursorPos(($x + 80 + 30), ($y + 34))
Start-Sleep -Seconds 3
Save-Screen (Join-Path $OutDir "v4_3_hover.png")

# 5. 日志中与自动朗读相关的错误
$log = Get-ChildItem (Join-Path $AppDir "PortableConfig\Logs") -Recurse -Filter *.log |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
Write-Host "=== 日志尾部"
Select-String -Path $log.FullName -Pattern "AutoSpeak|TTS|Speech|bubble" -SimpleMatch:$false |
    Select-Object -Last 6 | ForEach-Object { $_.Line.Substring(0, [Math]::Min(160, $_.Line.Length)) }
