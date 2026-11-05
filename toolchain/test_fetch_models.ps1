# 打开设置→常规，点「获取模型」，检查下拉里是否有模型
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class ModelFetch {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
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
  public static void CtrlComma(){
    keybd_event(0x11,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0xBC,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0xBC,0,2,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x11,0,2,IntPtr.Zero);
  }
}
"@

$p = Get-Process STranslate
[ModelFetch]::AltG()
Start-Sleep -Milliseconds 1300
$h = [ModelFetch]::Find([uint32]$p.Id, 'STranslate')
if ($h -ne [IntPtr]::Zero) { [void][ModelFetch]::ShowWindow($h, 5) }
Start-Sleep -Milliseconds 400
[ModelFetch]::CtrlComma()
Start-Sleep -Milliseconds 2000

$sh = [ModelFetch]::Find([uint32]$p.Id, '设置')
if ($sh -eq [IntPtr]::Zero) { Write-Output 'settings missing'; exit 1 }
$swin = [System.Windows.Automation.AutomationElement]::FromHandle($sh)

$btnCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Button)
$fetch = $null
foreach ($b in $swin.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCond)) {
    if ($b.Current.Name -eq '获取模型') { $fetch = $b }
}
Write-Output ("获取模型按钮: {0}" -f ($null -ne $fetch))

if ($fetch) {
    $fetch.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    Write-Output 'clicked, waiting models...'
    Start-Sleep -Seconds 8

    # 找模型下拉
    $comboCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::ComboBox)
    $combos = $swin.FindAll([System.Windows.Automation.TreeScope]::Descendants, $comboCond)
    Write-Output ("下拉数量: {0}" -f $combos.Count)
    foreach ($c in $combos) {
        $val = ''
        try { $val = $c.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value } catch { }
        if ($val -match 'gpt|deepseek|claude|glm|kimi|mimo|minimax') {
            Write-Output ("模型下拉当前值: {0}" -f $val)
            try {
                $c.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand()
                Start-Sleep -Milliseconds 800
                $liCond = New-Object System.Windows.Automation.PropertyCondition(
                    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                    [System.Windows.Automation.ControlType]::ListItem)
                $items = $c.FindAll([System.Windows.Automation.TreeScope]::Descendants, $liCond)
                Write-Output ("下拉项数量: {0}" -f $items.Count)
                $names = @()
                foreach ($i in $items) { if ($i.Current.Name) { $names += $i.Current.Name } }
                Write-Output ("模型: " + ($names -join ', '))
            } catch { }
        }
    }
}
