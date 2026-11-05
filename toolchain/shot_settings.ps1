Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type -AssemblyName System.Drawing

$proc = Get-Process STranslate
$root = [System.Windows.Automation.AutomationElement]::RootElement
$cond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $proc.Id)
$windows = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
$win = $null
foreach ($w in $windows) {
    if ($w.Current.ControlType -eq [System.Windows.Automation.ControlType]::Window) { $win = $w; break }
}
if (-not $win) { Write-Host "no window"; exit }

$r = $win.Current.BoundingRectangle
$wpx = [int]$r.Width; $hpx = [int]$r.Height
Write-Host "rect=$($r.X),$($r.Y) size=${wpx}x${hpx}"
$bmp = New-Object System.Drawing.Bitmap($wpx, $hpx)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen([int]$r.X, [int]$r.Y, 0, 0, $bmp.Size)
$g.Dispose()
$bmp.Save("D:\vibe_coding\english_learn\toolchain\panel_check.png")
$bmp.Dispose()
Write-Host "saved"
