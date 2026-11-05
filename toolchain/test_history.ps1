# 验证历史导航：翻译两个词后，点左箭头回到上一个
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class HistNav {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
  public static IntPtr Find(uint pid, string title){
    IntPtr f = IntPtr.Zero;
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid){ var sb=new StringBuilder(512); GetWindowText(h,sb,512); if(sb.ToString()==title){ f=h; return false; } } return true; }, IntPtr.Zero);
    return f;
  }
  public static void AltG(){
    keybd_event(0x12,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x47,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x47,0,2,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x12,0,2,IntPtr.Zero);
  }
}
"@

$p = Get-Process STranslate
[HistNav]::AltG()
Start-Sleep -Milliseconds 1400
$h = [HistNav]::Find([uint32]$p.Id, 'STranslate')
[void][HistNav]::ShowWindow($h, 5)
Start-Sleep -Milliseconds 400
[void][HistNav]::SetForegroundWindow($h)
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
if ($null -eq $win) { Write-Output 'UIA missing'; exit 1 }

$editCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Edit)
$edit = $win.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $editCond)

function Translate($word) {
    $edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($word)
    Start-Sleep -Milliseconds 500
    [void][HistNav]::SetForegroundWindow($h)
    Start-Sleep -Milliseconds 200
    (New-Object -ComObject WScript.Shell).SendKeys('{ENTER}')
    Start-Sleep -Seconds 3
    $v = $edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
    Write-Output ("  翻译: {0}" -f $v)
}

Translate 'canvas'
Translate 'campaign'
Translate 'stop'

$btnCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Button)
$back = $null
$fwd = $null
foreach ($b in $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCond)) {
    if ($b.Current.HelpText -eq '上一个翻译过的词') { $back = $b }
    if ($b.Current.HelpText -eq '下一个翻译过的词') { $fwd = $b }
}
Write-Output ("箭头按钮: back={0} forward={1}" -f ($null -ne $back), ($null -ne $fwd))

if ($back) {
    $back.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    Start-Sleep -Seconds 2
    $v = $edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
    Write-Output ("点左箭头后输入框: {0}  (期望 campaign)" -f $v)

    $back.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    Start-Sleep -Seconds 2
    $v = $edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
    Write-Output ("再点左箭头: {0}  (期望 canvas)" -f $v)

    if ($fwd) {
        $fwd.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        Start-Sleep -Seconds 2
        $v = $edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
        Write-Output ("点右箭头: {0}  (期望 campaign)" -f $v)
    }
}
