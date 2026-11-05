# 验证①：点开设置→生词本不崩溃；②遮罩尺寸不闪（连续拖拽后仍在）
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing, System.Windows.Forms

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class Fix3 {
  public delegate bool EP(IntPtr h, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint d1, uint d2, uint d3, IntPtr e);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
  public static IntPtr Find(uint pid, string title){
    IntPtr f = IntPtr.Zero;
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid){ var sb=new StringBuilder(512); GetWindowText(h,sb,512); if(sb.ToString()==title){ f=h; return false; } } return true; }, IntPtr.Zero);
    return f;
  }
  public static bool HasOverlay(uint pid){
    bool found = false;
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid){ var sb=new StringBuilder(512); GetWindowText(h,sb,512); if(sb.ToString()=="STranslateRegionOverlay") found=true; } return true; }, IntPtr.Zero);
    return found;
  }
  public static void PressAltQ(){
    keybd_event(0x12,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x51,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(90);
    keybd_event(0x51,0,2,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x12,0,2,IntPtr.Zero);
  }
  public static void Esc(){ keybd_event(0x1B,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(60); keybd_event(0x1B,0,2,IntPtr.Zero); }
}
"@

$p = Get-Process STranslate
$h = [Fix3]::Find([uint32]$p.Id, 'STranslate')
[Fix3]::Esc()
Start-Sleep -Milliseconds 400

# 显示主窗口并打开设置
[void][Fix3]::ShowWindow($h, 5)
Start-Sleep -Milliseconds 400
[void][Fix3]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 800

$rootEl = [System.Windows.Automation.AutomationElement]::RootElement
$pc = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
$win = $null
for ($i = 0; $i -lt 12; $i++) {
    foreach ($w in $rootEl.FindAll([System.Windows.Automation.TreeScope]::Children, $pc)) {
        if ($w.Current.Name -eq 'STranslate') { $win = $w }
    }
    if ($null -ne $win) { break }
    Start-Sleep -Milliseconds 300
}
if ($null -eq $win) { Write-Output 'UIA main missing'; exit 1 }

$btnCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Button)
$settingsBtn = $null
foreach ($b in $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCond)) {
    if ($b.Current.HelpText -eq '设置') { $settingsBtn = $b }
}
if ($null -eq $settingsBtn) { Write-Output 'settings button missing'; exit 1 }
$settingsBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
Start-Sleep -Milliseconds 1800

$sh = [Fix3]::Find([uint32]$p.Id, '设置')
if ($sh -eq [IntPtr]::Zero) { Write-Output '设置窗口未出现'; exit 1 }

$swin = [System.Windows.Automation.AutomationElement]::FromHandle($sh)
$navCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::NameProperty, '生词本')
$navItems = $swin.FindAll([System.Windows.Automation.TreeScope]::Descendants, $navCond)
$picked = $false
foreach ($n in $navItems) {
    try { $n.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); $picked = $true; break } catch { }
}
Write-Output ("NAV 生词本: {0}" -f $picked)
Start-Sleep -Milliseconds 2000

$alive = Get-Process STranslate -ErrorAction SilentlyContinue
Write-Output ("① 进程存活: {0}  (期望 True)" -f ($null -ne $alive))

if ($alive) {
    $texts = @()
    foreach ($e in $swin.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)) {
        if ($e.Current.ControlType -eq [System.Windows.Automation.ControlType]::Text -and $e.Current.Name) { $texts += $e.Current.Name }
    }
    Write-Output ("页面文本: " + ($texts -join ' | '))

    $r = New-Object Fix3+RECT
    [void][Fix3]::GetWindowRect($sh, [ref]$r)
    $w = $r.R - $r.L; $ht = $r.B - $r.T
    $bmp = New-Object System.Drawing.Bitmap($w, $ht)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size); $g.Dispose()
    $out = 'D:\vibe_coding\english_learn\toolchain\vocab_fixed.png'
    $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    Write-Output ("shotted -> {0}" -f $out)
}
