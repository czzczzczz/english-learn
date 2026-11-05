$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class K14 {
  public delegate bool EP(IntPtr h, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
  public const byte VK_CONTROL = 0x11;
  public const byte VK_MENU = 0x12;
  public const byte VK_G = 0x47;
  public const byte VK_OEM_COMMA = 0xBC;
  public const uint KEYUP = 0x0002;

  public static void ComboCtrl(byte vk){
    keybd_event(VK_CONTROL, 0, 0, IntPtr.Zero);
    System.Threading.Thread.Sleep(60);
    keybd_event(vk, 0, 0, IntPtr.Zero);
    System.Threading.Thread.Sleep(60);
    keybd_event(vk, 0, KEYUP, IntPtr.Zero);
    System.Threading.Thread.Sleep(60);
    keybd_event(VK_CONTROL, 0, KEYUP, IntPtr.Zero);
  }
  public static void ComboAltG(){
    keybd_event(VK_MENU, 0, 0, IntPtr.Zero);
    System.Threading.Thread.Sleep(60);
    keybd_event(VK_G, 0, 0, IntPtr.Zero);
    System.Threading.Thread.Sleep(60);
    keybd_event(VK_G, 0, KEYUP, IntPtr.Zero);
    System.Threading.Thread.Sleep(60);
    keybd_event(VK_MENU, 0, KEYUP, IntPtr.Zero);
  }
  public static IntPtr Find(uint pid, string title){
    IntPtr f = IntPtr.Zero;
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid){ var sb=new StringBuilder(512); GetWindowText(h,sb,512); if(sb.ToString()==title){ f=h; return false; } } return true; }, IntPtr.Zero);
    return f;
  }
  public static int[] Rect(IntPtr h){ RECT r; GetWindowRect(h, out r); return new int[]{ r.L, r.T, r.R, r.B }; }
  public static bool Snap(IntPtr h, IntPtr hdc){ return PrintWindow(h, hdc, 2); }
}
"@

$p = Get-Process STranslate

# 1) 显示主窗口（Alt+G），让应用自己走显示逻辑
[K14]::ComboAltG()
Start-Sleep -Milliseconds 1500
Write-Output 'ALT+G sent'

# 2) 打开设置（Ctrl+,）
[K14]::ComboCtrl([K14]::VK_OEM_COMMA)
Start-Sleep -Milliseconds 2200

$settings = [K14]::Find([uint32]$p.Id, '设置')
if ($settings -eq [IntPtr]::Zero) { Write-Output 'SETTINGS: not opened'; exit 1 }
Write-Output 'SETTINGS: opened'

# 3) 导航到生词本
$win = [System.Windows.Automation.AutomationElement]::FromHandle($settings)
$navCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::NameProperty, '热键')
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
Start-Sleep -Milliseconds 1800

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

# 4) 截图
$sr = [K14]::Rect($settings)
$sw = $sr[2] - $sr[0]; $sh = $sr[3] - $sr[1]
$bmp = New-Object System.Drawing.Bitmap($sw, $sh)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
$ok = [K14]::Snap($settings, $hdc)
$g.ReleaseHdc($hdc); $g.Dispose()
$out = 'D:\vibe_coding\english_learn\toolchain\vocab_page.png'
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
Write-Output ("SHOT {0}x{1} ok={2} -> {3}" -f $sw, $sh, $ok, $out)
