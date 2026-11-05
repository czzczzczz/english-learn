$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class W32 {
  public delegate bool EP(IntPtr h, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint a,uint b,uint c,IntPtr e);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  public const uint LD=0x0002, LU=0x0004;
  public static IntPtr Find(uint pid,string t){ IntPtr f=IntPtr.Zero; EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid){var sb=new StringBuilder(512); GetWindowText(h,sb,512); if(sb.ToString()==t){f=h;return false;}} return true;}, IntPtr.Zero); return f;}
  public static void Click(int x,int y){ SetCursorPos(x,y); System.Threading.Thread.Sleep(180); mouse_event(LD,0,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(60); mouse_event(LU,0,0,0,IntPtr.Zero); }
}
"@

$p = Get-Process STranslate
$root = [System.Windows.Automation.AutomationElement]::RootElement
$cond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
$main = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)

# 1) 点设置按钮（header 最右，x 约 1127）
$mr = $main.Current.BoundingRectangle
[void][W32]::SetForegroundWindow([W32]::Find([uint32]$p.Id, 'STranslate'))
Start-Sleep -Milliseconds 400
[W32]::Click(1140, 239)
Start-Sleep -Milliseconds 1800

# 2) 设置窗口
$h = [W32]::Find([uint32]$p.Id, '设置')
if ($h -eq [IntPtr]::Zero) { Write-Output 'SETTINGS-WINDOW: not found'; exit 1 }
Write-Output 'SETTINGS-WINDOW: found'

$win = $null
$wins = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
foreach ($w in $wins) { if ($w.Current.Name -eq '设置') { $win = $w; break } }
if ($null -eq $win) { Write-Output 'UIA: settings element missing'; exit 1 }

$dump = Join-Path 'D:\vibe_coding\english_learn\toolchain' 'tts_uia.txt'
$nav = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants,
    [System.Windows.Automation.Condition]::TrueCondition)
$lines = foreach ($e in $nav) {
    "{0} | {1} | {2}" -f $e.Current.ControlType.ProgrammaticName, $e.Current.Name, $e.Current.AutomationId
}
$lines | Set-Content -Path $dump -Encoding utf8
Write-Output ("UIA NODES: {0}" -f $nav.Count)

# 3) 点击导航「朗读」
$navCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::NameProperty, '朗读')
$navItems = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $navCond)
$selected = $false
foreach ($navItem in $navItems) {
    try {
        $sel = $navItem.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
        $sel.Select()
        Write-Output 'NAV: 朗读 selected'
        $selected = $true
        break
    } catch { }
}
if (-not $selected) { Write-Output 'NAV: already on page (no selectable nav item)' }
Start-Sleep -Milliseconds 1500

# 4) 页面控件清单（验证设置项真的渲染出来）
$after = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants,
    [System.Windows.Automation.Condition]::TrueCondition)
$cbs = @()
foreach ($e in $after) {
    if ($e.Current.ControlType -eq [System.Windows.Automation.ControlType]::ComboBox) {
        $cbs += ("{0} = '{1}'" -f $e.Current.Name, $e.Current.HelpText)
    }
}
Write-Output ("COMBOBOX COUNT: {0}" -f $cbs.Count)
$cbs | ForEach-Object { Write-Output ("  " + $_) }

$btnNames = @()
foreach ($e in $after) {
    if ($e.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button -and $e.Current.Name) {
        $btnNames += $e.Current.Name
    }
}
Write-Output ("BUTTONS: " + ($btnNames -join ' / '))

# 5) PrintWindow 截图
$r = New-Object W32+RECT
[void][W32]::GetWindowRect($h, [ref]$r)
$w = $r.R - $r.L; $ht = $r.B - $r.T
Write-Output ("RECT: {0},{1} {2}x{3}" -f $r.L, $r.T, $w, $ht)
$bmp = New-Object System.Drawing.Bitmap($w, $ht)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
$ok = [W32]::PrintWindow($h, $hdc, 2)
$g.ReleaseHdc($hdc)
$g.Dispose()
$out = 'D:\vibe_coding\english_learn\toolchain\tts_page.png'
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output ("PRINTWINDOW: {0}  -> {1}  ({2:N0} bytes)" -f $ok, $out, (Get-Item $out).Length)
