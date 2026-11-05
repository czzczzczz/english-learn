# 实测：左键长按 450ms → 遮罩出现 → 拖框 → 松手 → 识别并翻译
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing, System.Windows.Forms

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class LongPressTest {
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
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);

  public static IntPtr Find(uint pid, string title){
    IntPtr f = IntPtr.Zero;
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid){ var sb=new StringBuilder(512); GetWindowText(h,sb,512); if(sb.ToString()==title){ f=h; return false; } } return true; }, IntPtr.Zero);
    return f;
  }
  public static string[] ListVisible(uint pid){
    var res = new System.Collections.Generic.List<string>();
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid && IsWindowVisible(h)){ var sb=new StringBuilder(512); GetWindowText(h,sb,512); RECT r; GetWindowRect(h, out r); res.Add("'" + sb.ToString() + "' " + (r.R-r.L) + "x" + (r.B-r.T)); } return true; }, IntPtr.Zero);
    return res.ToArray();
  }
  public static void Down(){ mouse_event(0x0002,0,0,0,IntPtr.Zero); }
  public static void Up(){ mouse_event(0x0004,0,0,0,IntPtr.Zero); }
  public static void MoveBy(int dx, int dy){ mouse_event(0x0001,(uint)dx,(uint)dy,0,IntPtr.Zero); }
  public static void AltG(){
    keybd_event(0x12,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x47,0,0,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x47,0,2,IntPtr.Zero); System.Threading.Thread.Sleep(60);
    keybd_event(0x12,0,2,IntPtr.Zero);
  }
}
"@

$p = Get-Process STranslate
$main = [LongPressTest]::Find([uint32]$p.Id, 'STranslate')

# 准备一块带英文的区域：打开记事本写到屏幕
$np = Start-Process 'C:\Windows\System32\notepad.exe' -PassThru
Start-Sleep -Seconds 2
[void][LongPressTest]::SetWindowPos($np.MainWindowHandle, [IntPtr]::Zero, 150, 200, 900, 260, 0x0040)
Start-Sleep -Milliseconds 400
[void][LongPressTest]::SetForegroundWindow($np.MainWindowHandle)
Start-Sleep -Milliseconds 600
Set-Clipboard -Value 'Learning English is easier when you listen every day.'
(New-Object -ComObject WScript.Shell).SendKeys('^v')
Start-Sleep -Milliseconds 800

Write-Output ("visible windows before: " + ([LongPressTest]::ListVisible([uint32]$p.Id) -join ' / '))

# 长按：按下 → 停 700ms（>450）→ 遮罩应出现
[LongPressTest]::SetCursorPos(200, 240)
Start-Sleep -Milliseconds 300
[LongPressTest]::Down()
Start-Sleep -Milliseconds 750

Write-Output ("after long-press hold: " + ([LongPressTest]::ListVisible([uint32]$p.Id) -join ' / '))
[LongPressTest]::Up()
Start-Sleep -Milliseconds 900
Write-Output ("after release (sticky overlay should stay): " + ([LongPressTest]::ListVisible([uint32]$p.Id) -join ' / '))

# 在遮罩上拖框选区（记事本文字区域）
[LongPressTest]::SetCursorPos(180, 230)
Start-Sleep -Milliseconds 200
[LongPressTest]::Down()
Start-Sleep -Milliseconds 100
for ($i = 0; $i -lt 30; $i++) { [LongPressTest]::MoveBy(20, 0); Start-Sleep -Milliseconds 20 }
for ($i = 0; $i -lt 6; $i++) { [LongPressTest]::MoveBy(0, 8); Start-Sleep -Milliseconds 20 }
Start-Sleep -Milliseconds 150
[LongPressTest]::Up()
Write-Output 'drag done'
Start-Sleep -Seconds 3

# 看主窗口是否被填了识别文字
Start-Sleep -Milliseconds 500
[LongPressTest]::AltG()
Start-Sleep -Milliseconds 1200
[void][LongPressTest]::SetWindowPos($main, [IntPtr]::Zero, 760, 120, 400, 700, 0x0040)
Start-Sleep -Milliseconds 800

Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$rootEl = [System.Windows.Automation.AutomationElement]::RootElement
$pc = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
$win = $null
for ($i = 0; $i -lt 10; $i++) {
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
        Write-Output ("INPUT TEXT: '" + $val + "'")
    } else { Write-Output 'input box not found' }
} else { Write-Output 'main window not found' }

Stop-Process -Id $np.Id -Force -ErrorAction SilentlyContinue
