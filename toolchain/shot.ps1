# 截取指定进程的主窗口（PrintWindow + PW_RENDERFULLCONTENT，不受遮挡影响）
param(
    [string]$ProcessName = "STranslate",
    [string]$OutFile = "D:\vibe_coding\english_learn\toolchain\shot.png"
)

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32Shot {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@

$proc = Get-Process -Name $ProcessName -ErrorAction Stop | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $proc) { Write-Error "未找到带窗口的进程 $ProcessName"; exit 1 }

$hwnd = $proc.MainWindowHandle
$rect = New-Object Win32Shot+RECT
[void][Win32Shot]::GetWindowRect($hwnd, [ref]$rect)
$width = $rect.Right - $rect.Left
$height = $rect.Bottom - $rect.Top
Write-Host "hwnd=$hwnd size=${width}x${height} visible=$([Win32Shot]::IsWindowVisible($hwnd))"

$bmp = New-Object System.Drawing.Bitmap($width, $height)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
# 2 = PW_RENDERFULLCONTENT，窗口被遮挡也能截到自身内容
$ok = [Win32Shot]::PrintWindow($hwnd, $hdc, 2)
$g.ReleaseHdc($hdc)
$g.Dispose()
Write-Host "PrintWindow=$ok"

$bmp.Save($OutFile, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host "saved $OutFile"
