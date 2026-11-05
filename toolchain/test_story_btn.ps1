# 点击「AI 故事」按钮：未配置时应弹出提示且不崩溃
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class StoryTest {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  public static IntPtr Find(uint pid, string title){
    IntPtr f = IntPtr.Zero;
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid){ var sb=new StringBuilder(512); GetWindowText(h,sb,512); if(sb.ToString()==title){ f=h; return false; } } return true; }, IntPtr.Zero);
    return f;
  }
}
"@

$p = Get-Process STranslate
$sh = [StoryTest]::Find([uint32]$p.Id, '设置')
if ($sh -eq [IntPtr]::Zero) { Write-Output 'settings window missing'; exit 1 }
$swin = [System.Windows.Automation.AutomationElement]::FromHandle($sh)

$btnCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Button)
$story = $null
foreach ($b in $swin.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCond)) {
    if ($b.Current.Name -eq 'AI 故事') { $story = $b }
}
Write-Output ("AI 故事按钮: {0}" -f ($null -ne $story))

if ($story) {
    $story.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    Start-Sleep -Seconds 2
    $alive = Get-Process STranslate -ErrorAction SilentlyContinue
    Write-Output ("点击后进程存活: {0}  (期望 True)" -f ($null -ne $alive))

    # 读取页面文本，看是否有提示
    $texts = @()
    foreach ($e in $swin.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)) {
        if ($e.Current.ControlType -eq [System.Windows.Automation.ControlType]::Text -and $e.Current.Name -match '配置|中转站|密钥') { $texts += $e.Current.Name }
    }
    Write-Output ("提示文本: " + ($texts -join ' | '))
}
