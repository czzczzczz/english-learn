$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

Add-Type @"
using System; using System.Runtime.InteropServices;
public class Ui6 {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);
}
"@

# 1) 主窗口截图 + 文本清单
$app = Get-Process STranslate | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
Write-Output ("APP PID: {0}  VISIBLE: {1}" -f $app.Id, $app.MainWindowTitle)

$r = New-Object Ui6+RECT
[void][Ui6]::GetWindowRect($app.MainWindowHandle, [ref]$r)
$w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
$bmp = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
$ok = [Ui6]::PrintWindow($app.MainWindowHandle, $hdc, 2)
$g.ReleaseHdc($hdc); $g.Dispose()
$out = 'D:\vibe_coding\english_learn\toolchain\rg2_window.png'
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
Write-Output ("SHOT {0}x{1} printWindow={2} -> {3}" -f $w, $h, $ok, $out)

$root = [System.Windows.Automation.AutomationElement]::RootElement
$cond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $app.Id)
$main = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
$texts = $main.FindAll([System.Windows.Automation.TreeScope]::Descendants,
    [System.Windows.Automation.Condition]::TrueCondition)
$names = @()
foreach ($e in $texts) {
    if ($e.Current.ControlType -eq [System.Windows.Automation.ControlType]::Text -and $e.Current.Name) {
        $names += $e.Current.Name
    }
}
Write-Output ("TEXTS ({0}):" -f $names.Count)
$names | Select-Object -First 20 | ForEach-Object { Write-Output ("  " + $_) }

# 2) 结构化日志行（跳过超长 HTML 行）
$log = 'D:\vibe_coding\STranslate-dev\PortableConfig\Logs\1.0.0\20261103.log'
Write-Output '=== 21:55:29 之后的短日志 ==='
Get-Content $log | Where-Object {
    $_.Length -lt 400 -and $_ -match '2026-11-03 21:55:(2[9]|3[0-9]|4[0-9])' -and
    $_ -match 'MouseSelection|dictvoice|AudioPlayer|Translate|HttpGet|HTTP (request|response)|BingDic|Caiyun|Dictionary'
} | Select-Object -First 30
