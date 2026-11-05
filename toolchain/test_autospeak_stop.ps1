$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing, System.Windows.Forms

Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class V21 {
  public delegate bool EP(IntPtr h, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  public static IntPtr Find(uint pid, string title){
    IntPtr f = IntPtr.Zero;
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid){ var sb=new StringBuilder(512); GetWindowText(h,sb,512); if(sb.ToString()==title){ f=h; return false; } } return true; }, IntPtr.Zero);
    return f;
  }
  public static int[] Rect(IntPtr h){ RECT r; GetWindowRect(h, out r); return new int[]{ r.L, r.T, r.R, r.B }; }
}
"@

$logPath = 'D:\vibe_coding\STranslate-dev\PortableConfig\Logs\1.0.0'
$logFile = Get-ChildItem $logPath -Filter *.log | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$base = (Get-Content $logFile.FullName).Count

$app = Get-Process STranslate
$mainHwnd = [V21]::Find([uint32]$app.Id, 'STranslate')
if ($mainHwnd -eq [IntPtr]::Zero) { Write-Output 'MAIN: missing'; exit 1 }

# 记事本准备文本
$np = Start-Process 'C:\Windows\System32\notepad.exe' -PassThru
Start-Sleep -Seconds 2
[void][V21]::SetWindowPos($np.MainWindowHandle, [IntPtr]::Zero, 120, 120, 1000, 380, 0x0040)
Start-Sleep -Milliseconds 400
[void][V21]::SetForegroundWindow($np.MainWindowHandle)
Start-Sleep -Milliseconds 700
Set-Clipboard -Value 'world'
(New-Object -ComObject WScript.Shell).SendKeys('^v')
Start-Sleep -Milliseconds 900

$pt = New-Object V21+POINT
[void][V21]::ClientToScreen($np.MainWindowHandle, [ref]$pt)
$startX = $pt.X + 45
$y = $pt.Y + 22

[void][V21]::SetCursorPos($startX, $y)
Start-Sleep -Milliseconds 300
[void][V21]::SetCursorPos(($startX + 6), $y)
Start-Sleep -Milliseconds 700

[V21]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 60
for ($i = 1; $i -le 6; $i++) {
    [V21]::mouse_event(0x0001, 8, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 40
}
[V21]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 700

# 悬停气泡
[void][V21]::SetCursorPos(($startX + 54 + 30), ($y + 34))
Write-Output 'HOVER: bubble'

# 轮询主窗口是否出现停止按钮（自动朗读正在播放）
$win = [System.Windows.Automation.AutomationElement]::FromHandle($mainHwnd)
$btnCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Button)

$stopBtn = $null
$seenAt = -1
for ($t = 0; $t -lt 120; $t++) {
    Start-Sleep -Milliseconds 50
    $btns = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCond)
    foreach ($b in $btns) {
        if ($b.Current.HelpText -eq '取消') { $stopBtn = $b; $seenAt = $t * 50 }
    }
    if ($stopBtn) { break }
}

Write-Output ("AUTO-SPEAK STOP BUTTON: {0} (at {1} ms)" -f ($null -ne $stopBtn), $seenAt)

if ($stopBtn) {
    $stopBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    Write-Output 'STOP: invoked'
}
Start-Sleep -Milliseconds 2500

Stop-Process -Id $np.Id -Force -ErrorAction SilentlyContinue

Write-Output '=== 新增日志 ==='
Get-Content $logFile.FullName | Select-Object -Skip $base |
    Where-Object { $_.Length -lt 300 -and $_ -match 'Auto speak|AudioPlayer|dictvoice|tts' } |
    Select-Object -First 15
