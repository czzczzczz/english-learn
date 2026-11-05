$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class W13 {
  public delegate bool EP(IntPtr h, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
  public static IntPtr Find(uint pid, string title){
    IntPtr f = IntPtr.Zero;
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid){ var sb=new StringBuilder(512); GetWindowText(h,sb,512); if(sb.ToString()==title){ f=h; return false; } } return true; }, IntPtr.Zero);
    return f;
  }
  public static int[] Rect(IntPtr h){ RECT r; GetWindowRect(h, out r); return new int[]{ r.L, r.T, r.R, r.B }; }
  public static void Click(int x, int y){ SetCursorPos(x,y); System.Threading.Thread.Sleep(120); mouse_event(0x0002,0,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(60); mouse_event(0x0004,0,0,0,IntPtr.Zero); }
  public static bool Snap(IntPtr h, IntPtr hdc){ return PrintWindow(h, hdc, 2); }
}
"@

$p = Get-Process STranslate
$main = [W13]::Find([uint32]$p.Id, 'STranslate')
if ($main -eq [IntPtr]::Zero) { Write-Output 'MAIN HWND: missing'; exit 1 }

[void][W13]::ShowWindow($main, 5)
Start-Sleep -Milliseconds 300
[void][W13]::SetForegroundWindow($main)
Start-Sleep -Milliseconds 700

$r = [W13]::Rect($main)
Write-Output ("MAIN RECT: {0},{1} {2}x{3}" -f $r[0], $r[1], ($r[2]-$r[0]), ($r[3]-$r[1]))

# 设置按钮位于标题栏右侧倒数第二个图标，按窗口宽度相对定位
$w = $r[2] - $r[0]
[W13]::Click(($r[0] + $w - 33), ($r[1] + 18))
Start-Sleep -Milliseconds 2000

$settings = [W13]::Find([uint32]$p.Id, '设置')
if ($settings -eq [IntPtr]::Zero) { Write-Output 'SETTINGS: not opened'; exit 1 }
Write-Output 'SETTINGS: opened'

$win = [System.Windows.Automation.AutomationElement]::FromHandle($settings)
$navCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::NameProperty, '生词本')
$navItems = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $navCond)
$picked = $false
foreach ($n in $navItems) {
    try {
        $n.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
        $picked = $true
        break
    } catch { }
}
Write-Output ("NAV 生词本: {0} (candidates={1})" -f $picked, $navItems.Count)
Start-Sleep -Milliseconds 1600

$all = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants,
    [System.Windows.Automation.Condition]::TrueCondition)
$texts = @()
$buttons = @()
foreach ($e in $all) {
    if ($e.Current.ControlType -eq [System.Windows.Automation.ControlType]::Text -and $e.Current.Name) { $texts += $e.Current.Name }
    if ($e.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button -and $e.Current.Name) { $buttons += $e.Current.Name }
}
Write-Output ("PAGE TEXTS: " + ($texts -join ' | '))
Write-Output ("PAGE BUTTONS: " + ($buttons -join ' / '))

$sr = [W13]::Rect($settings)
$sw = $sr[2] - $sr[0]; $sh = $sr[3] - $sr[1]
$bmp = New-Object System.Drawing.Bitmap($sw, $sh)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
$ok = [W13]::Snap($settings, $hdc)
$g.ReleaseHdc($hdc); $g.Dispose()
$out = 'D:\vibe_coding\english_learn\toolchain\vocab_page.png'
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
Write-Output ("SHOT {0}x{1} ok={2} -> {3}" -f $sw, $sh, $ok, $out)
