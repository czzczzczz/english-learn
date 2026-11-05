$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class V18 {
  public delegate bool EP(IntPtr h, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
  public static IntPtr Find(uint pid, string title){
    IntPtr f = IntPtr.Zero;
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid){ var sb=new StringBuilder(512); GetWindowText(h,sb,512); if(sb.ToString()==title){ f=h; return false; } } return true; }, IntPtr.Zero);
    return f;
  }
  public static int[] Rect(IntPtr h){ RECT r; GetWindowRect(h, out r); return new int[]{ r.L, r.T, r.R, r.B }; }
  public static bool Snap(IntPtr h, IntPtr hdc){ return PrintWindow(h, hdc, 2); }
  public static void AltG(){
    keybd_event(0x12,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x47,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x47,0,2,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x12,0,2,IntPtr.Zero);
  }
}
"@

$json = 'D:\vibe_coding\STranslate-dev\PortableConfig\Settings\Vocabulary.json'
Write-Output ("JSON BEFORE: " + (Get-Content $json -Raw))

$p = Get-Process STranslate
$main = [V18]::Find([uint32]$p.Id, 'STranslate')
if ($main -eq [IntPtr]::Zero) { Write-Output 'MAIN: missing'; exit 1 }
[void][V18]::ShowWindow($main, 5)
Start-Sleep -Milliseconds 300
[void][V18]::SetForegroundWindow($main)
Start-Sleep -Milliseconds 800

$win = [System.Windows.Automation.AutomationElement]::FromHandle($main)
$editCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Edit)
$edit = $win.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $editCond)
if ($null -eq $edit) { Write-Output 'INPUT: edit missing'; exit 1 }
$edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('campaign')
Write-Output 'INPUT: campaign'
Start-Sleep -Milliseconds 900

function Get-BookmarkButtons($rootEl) {
    $c = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Button)
    $all = $rootEl.FindAll([System.Windows.Automation.TreeScope]::Descendants, $c)
    $res = @()
    foreach ($b in $all) {
        if ($b.Current.HelpText -match '生词本') { $res += $b }
    }
    return $res
}

$marks = Get-BookmarkButtons $win
Write-Output ("BOOKMARK BUTTONS: {0}" -f $marks.Count)
foreach ($m in $marks) { Write-Output ("  help='{0}'" -f $m.Current.HelpText) }

function Snap-Main($tag) {
    $r = [V18]::Rect($main)
    $w = $r[2] - $r[0]; $h = $r[3] - $r[1]
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc()
    $ok = [V18]::Snap($main, $hdc)
    $g.ReleaseHdc($hdc); $g.Dispose()
    $out = "D:\vibe_coding\english_learn\toolchain\vocab_btn_$tag.png"
    $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    Write-Output ("SHOT $tag ${w}x${h} ok=$ok -> $out")
}

Snap-Main 'off'

# 第一次点：加入
$btn = $marks[0]
$btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
Start-Sleep -Milliseconds 1200
Write-Output ("JSON AFTER ADD: " + (Get-Content $json -Raw))
Snap-Main 'on'

$marks2 = Get-BookmarkButtons $win
foreach ($m in $marks2) { Write-Output ("  help after add='{0}'" -f $m.Current.HelpText) }

# 第二次点：移除
$marks2[0].GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
Start-Sleep -Milliseconds 1200
Write-Output ("JSON AFTER TOGGLE OFF: " + (Get-Content $json -Raw))
