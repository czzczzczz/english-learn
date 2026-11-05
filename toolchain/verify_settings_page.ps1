$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing
Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class S1 {
  public delegate bool EP(IntPtr h, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint a,uint b,uint c,IntPtr e);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint f);
  public const uint LD=0x0002, LU=0x0004;
  public static IntPtr Find(uint pid,string t,bool visibleOnly){ IntPtr f=IntPtr.Zero; EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid && (!visibleOnly || IsWindowVisible(h))){var sb=new StringBuilder(512); GetWindowText(h,sb,512); if(sb.ToString()==t){f=h;return false;}} return true;}, IntPtr.Zero); return f;}
  public static int[] Rect(IntPtr h){ RECT r; GetWindowRect(h, out r); return new int[]{ r.L, r.T, r.R, r.B }; }
  public static void Click(int x,int y){ SetCursorPos(x,y); System.Threading.Thread.Sleep(200); mouse_event(LD,0,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(70); mouse_event(LU,0,0,0,IntPtr.Zero); }
  public static bool Snap(IntPtr h, IntPtr hdc){ return PrintWindow(h, hdc, 2); }
}
"@
$p = Get-Process STranslate
$main = [S1]::Find([uint32]$p.Id, 'STranslate', $true)
if ($main -eq [IntPtr]::Zero) { Write-Output 'MAIN: hidden'; exit 1 }
$r = [S1]::Rect($main)
Write-Output ("MAIN rect={0},{1},{2},{3}" -f $r[0],$r[1],$r[2],$r[3])
[void][S1]::SetForegroundWindow($main)
Start-Sleep -Milliseconds 500
# 齿轮按钮在头栏最右侧
$x = $r[2] - 29; $y = $r[1] + 26
Write-Output ("CLICK gear at {0},{1}" -f $x,$y)
[S1]::Click($x,$y)
Start-Sleep -Milliseconds 2000
$titles = @('设置','Settings')
$hw = [IntPtr]::Zero; $usedTitle = ''
foreach ($t in $titles) { $hh = [S1]::Find([uint32]$p.Id, $t, $true); if ($hh -ne [IntPtr]::Zero) { $hw = $hh; $usedTitle = $t; break } }
if ($hw -eq [IntPtr]::Zero) { Write-Output 'SETTINGS: not found'; exit 1 }
Write-Output ("SETTINGS: found title='{0}'" -f $usedTitle)

$root = [System.Windows.Automation.AutomationElement]::RootElement
$cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
$win = $null
foreach ($w in $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)) { if ($w.Current.Name -eq $usedTitle) { $win = $w; break } }
if ($null -eq $win) { Write-Output 'UIA: settings element missing'; exit 1 }

# 导航「朗读」
$navCond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, '朗读')
$picked = $false
foreach ($navItem in $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $navCond)) {
  try { $navItem.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); $picked = $true; break } catch { }
}
Write-Output ("NAV 朗读 selected={0}" -f $picked)
Start-Sleep -Milliseconds 1500

$all = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
$cbs = @(); $btns = @(); $texts = @()
foreach ($e in $all) {
  $ct = $e.Current.ControlType
  if ($ct -eq [System.Windows.Automation.ControlType]::ComboBox) { $cbs += ("'{0}' value='{1}'" -f $e.Current.Name, $e.Current.HelpText) }
  if ($ct -eq [System.Windows.Automation.ControlType]::Button -and $e.Current.Name) { $btns += $e.Current.Name }
}
Write-Output ("COMBOBOX COUNT: {0}" -f $cbs.Count)
$cbs | ForEach-Object { Write-Output ("  " + $_) }
Write-Output ("BUTTONS: " + ($btns -join ' / '))

$rr = [S1]::Rect($hw); $w = $rr[2]-$rr[0]; $ht = $rr[3]-$rr[1]
$bmp = New-Object System.Drawing.Bitmap($w,$ht); $g = [System.Drawing.Graphics]::FromImage($bmp); $hdc = $g.GetHdc()
$ok = [S1]::Snap($hw, $hdc); $g.ReleaseHdc($hdc); $g.Dispose()
$out = 'D:\vibe_coding\english_learn\toolchain\settings_render.png'
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
Write-Output ("PRINTWINDOW ok={0} {1}x{2} -> {3} ({4:N0} bytes)" -f $ok,$w,$ht,$out,(Get-Item $out).Length)
