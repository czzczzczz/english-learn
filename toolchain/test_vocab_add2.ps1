$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

Add-Type @"
using System; using System.Runtime.InteropServices;
public class K15 {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
  public static void ComboAltG(){
    keybd_event(0x12,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x47,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x47,0,2,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x12,0,2,IntPtr.Zero);
  }
}
"@

$jsonPath = 'D:\vibe_coding\STranslate-dev\PortableConfig\Settings\Vocabulary.json'
if (Test-Path $jsonPath) { Remove-Item $jsonPath -Force; Write-Output 'RESET: json removed' }

[K15]::ComboAltG()
Start-Sleep -Milliseconds 1500

$p = Get-Process STranslate
$root = [System.Windows.Automation.AutomationElement]::RootElement
$cond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
$wins = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
Write-Output ("TOP WINDOWS: {0}" -f $wins.Count)
$main = $null
foreach ($w in $wins) { if ($w.Current.Name -eq 'STranslate') { $main = $w } }
if ($null -eq $main) { Write-Output 'MAIN: missing'; exit 1 }

$editCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Edit)
$edit = $main.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $editCond)
$edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('hello')
Write-Output 'INPUT: hello'
Start-Sleep -Milliseconds 600

$btnCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Button)
$btns = $main.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCond)
$target = $null
foreach ($b in $btns) { if ($b.Current.HelpText -eq '添加到生词本') { $target = $b } }
if ($null -eq $target) { Write-Output 'VOCAB BTN: missing'; exit 1 }
$target.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
Write-Output 'VOCAB: invoked'
Start-Sleep -Milliseconds 1200

if (Test-Path $jsonPath) {
    Write-Output '--- JSON ---'
    Get-Content $jsonPath -Raw
} else { Write-Output 'JSON: not created' }
