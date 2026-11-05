$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class W12 {
  public delegate bool EP(IntPtr h, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  public static IntPtr Find(uint pid, string title){
    IntPtr f = IntPtr.Zero;
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid){ var sb=new StringBuilder(512); GetWindowText(h,sb,512); if(sb.ToString()==title){ f=h; return false; } } return true; }, IntPtr.Zero);
    return f;
  }
}
"@

$p = Get-Process STranslate
$root = [System.Windows.Automation.AutomationElement]::RootElement
$cond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)

# 用句柄直接取主窗口元素，避免隐藏/显示切换后 UIA 缓存不一致
$mainHwnd = [W12]::Find([uint32]$p.Id, 'STranslate')
if ($mainHwnd -eq [IntPtr]::Zero) { Write-Output 'MAIN HWND: missing'; exit 1 }
$main = [System.Windows.Automation.AutomationElement]::FromHandle($mainHwnd)
Write-Output ("MAIN: hwnd={0} name='{1}'" -f $mainHwnd, $main.Current.Name)

$btnCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Button)
$btns = $main.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCond)
$settingsBtn = $null
foreach ($b in $btns) { if ($b.Current.HelpText -eq '设置') { $settingsBtn = $b } }
if ($null -eq $settingsBtn) {
    Write-Output ("BTN DUMP: {0}" -f $btns.Count)
    foreach ($b in $btns) { Write-Output ("  help='{0}'" -f $b.Current.HelpText) }
}
if ($settingsBtn) {
    $settingsBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    Start-Sleep -Milliseconds 1800
    Write-Output 'SETTINGS: opened'
} else { Write-Output 'SETTINGS BUTTON: missing'; exit 1 }

$win = $null
$wins = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
foreach ($w in $wins) { if ($w.Current.Name -eq '设置') { $win = $w } }
if ($null -eq $win) { Write-Output 'SETTINGS WINDOW: missing'; exit 1 }

# 导航到生词本
$navCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::NameProperty, '生词本')
$navItems = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $navCond)
$selected = $false
foreach ($n in $navItems) {
    try {
        $n.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
        $selected = $true
        break
    } catch { }
}
Write-Output ("NAV 生词本: {0}" -f $selected)
Start-Sleep -Milliseconds 1500

# 页面内容清单
$all = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants,
    [System.Windows.Automation.Condition]::TrueCondition)
$texts = @()
foreach ($e in $all) {
    if ($e.Current.ControlType -eq [System.Windows.Automation.ControlType]::Text -and $e.Current.Name) {
        $texts += $e.Current.Name
    }
}
Write-Output ("TEXTS: " + ($texts -join ' | '))

# 截图
$h = [W12]::Find([uint32]$p.Id, '设置')
if ($h -ne [IntPtr]::Zero) {
    $r = New-Object W12+RECT
    [void][W12]::GetWindowRect($h, [ref]$r)
    $w = $r.R - $r.L; $ht = $r.B - $r.T
    $bmp = New-Object System.Drawing.Bitmap($w, $ht)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc()
    $ok = [W12]::PrintWindow($h, $hdc, 2)
    $g.ReleaseHdc($hdc); $g.Dispose()
    $out = 'D:\vibe_coding\english_learn\toolchain\vocab_page.png'
    $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    Write-Output ("SHOT {0}x{1} ok={2} -> {3}" -f $w, $ht, $ok, $out)
}
