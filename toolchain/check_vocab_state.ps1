$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class V19 {
  public delegate bool EP(IntPtr h, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
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
$main = [V19]::Find([uint32]$p.Id, 'STranslate')
if ($main -eq [IntPtr]::Zero) { Write-Output 'MAIN: missing'; exit 1 }
[void][V19]::ShowWindow($main, 5)
Start-Sleep -Milliseconds 400
[void][V19]::SetForegroundWindow($main)
Start-Sleep -Milliseconds 600

$win = [System.Windows.Automation.AutomationElement]::FromHandle($main)
$editCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Edit)
$edit = $win.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $editCond)
$current = $edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
Write-Output ("INPUT VALUE: '{0}'" -f $current)

$btnCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Button)
$btns = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCond)
foreach ($b in $btns) {
    if ($b.Current.HelpText -match '生词本') {
        Write-Output ("BOOKMARK HELP: '{0}'" -f $b.Current.HelpText)
    }
}

$r = [V19]::Rect($main)
$w = $r[2] - $r[0]; $h = $r[3] - $r[1]
$bmp = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
$ok = [V19]::Snap($main, $hdc)
$g.ReleaseHdc($hdc); $g.Dispose()
$out = 'D:\vibe_coding\english_learn\toolchain\vocab_btn_state.png'
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
Write-Output ("SHOT ${w}x${h} ok=$ok -> $out")
