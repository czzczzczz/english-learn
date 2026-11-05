# 读取主窗口输入框内容 + 截图，确认 OCR 结果已填入
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class ReadOut {
  public delegate bool EP(IntPtr h, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
  public static IntPtr Find(uint pid, string title){
    IntPtr f = IntPtr.Zero;
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid){ var sb=new StringBuilder(512); GetWindowText(h,sb,512); if(sb.ToString()==title){ f=h; return false; } } return true; }, IntPtr.Zero);
    return f;
  }
  public static int[] Rect(IntPtr h){ RECT r; GetWindowRect(h, out r); return new int[]{ r.L, r.T, r.R, r.B }; }
  public static void AltG(){
    keybd_event(0x12,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x47,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x47,0,2,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x12,0,2,IntPtr.Zero);
  }
}
"@

$p = Get-Process STranslate
[ReadOut]::AltG()
Start-Sleep -Milliseconds 1800
$h = [ReadOut]::Find([uint32]$p.Id, 'STranslate')
if ($h -eq [IntPtr]::Zero) { Write-Output 'MAIN: missing'; exit 1 }

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

if ($win) {
    $editCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Edit)
    $edit = $win.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $editCond)
    if ($edit) {
        $val = $edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
        Write-Output ("INPUT TEXT: [" + $val + "]")
    } else { Write-Output 'input not found' }
} else { Write-Output 'uia main missing' }

$r = [ReadOut]::Rect($h)
$w = $r[2] - $r[0]; $ht = $r[3] - $r[1]
Write-Output ("RECT: {0},{1} {2}x{3}" -f $r[0], $r[1], $w, $ht)
$bmp = New-Object System.Drawing.Bitmap($w, $ht)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
$ok = [ReadOut]::PrintWindow($h, $hdc, 2)
$g.ReleaseHdc($hdc); $g.Dispose()
$out = 'D:\vibe_coding\english_learn\toolchain\ocr_result_window.png'
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
Write-Output ("SHOT ok={0} -> {1} ({2:N0} bytes)" -f $ok, $out, (Get-Item $out).Length)
