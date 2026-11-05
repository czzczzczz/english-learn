$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class E1 {
  public delegate bool EP(IntPtr h, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X,Y; }
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint f);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  public static IntPtr FindAny(uint pid, string title){
    IntPtr f=IntPtr.Zero;
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid){var sb=new StringBuilder(512); GetWindowText(h,sb,512); if(sb.ToString()==title){f=h;return false;}} return true;}, IntPtr.Zero);
    return f;
  }
  public static int[] Rect(IntPtr h){ RECT r; GetWindowRect(h, out r); return new int[]{ r.L, r.T, r.R, r.B }; }
  public static bool Snap(IntPtr h, IntPtr hdc){ return PrintWindow(h, hdc, 2); }
}
"@
function Save-Bitmap([IntPtr]$hwnd, [string]$path) {
  $r = [E1]::Rect($hwnd); $w = $r[2]-$r[0]; $h = $r[3]-$r[1]
  if ($w -le 0 -or $h -le 0) { Write-Output "invalid size for $path"; return }
  $bmp = New-Object System.Drawing.Bitmap($w,$h)
  $g = [System.Drawing.Graphics]::FromImage($bmp); $hdc = $g.GetHdc()
  $ok = [E1]::Snap($hwnd, $hdc); $g.ReleaseHdc($hdc); $g.Dispose()
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
  Write-Output ("shot {0}x{1} ok={2} -> {3}" -f $w,$h,$ok,$path)
}

$AppDir = 'D:\vibe_coding\STranslate-dev'
$log = Get-ChildItem (Join-Path $AppDir 'PortableConfig\Logs') -Recurse -Filter *.log | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$base = (Get-Content $log.FullName).Count
Write-Output ("LOG: {0} BASELINE {1}" -f $log.Name, $base)

$app = Get-Process STranslate | Select-Object -First 1
$hwnd = [E1]::FindAny([uint32]$app.Id, 'STranslate')
if ($hwnd -eq [IntPtr]::Zero) { Write-Output 'APP WINDOW: missing'; exit 1 }
[void][E1]::ShowWindow($hwnd, 5)
Start-Sleep -Milliseconds 600
Write-Output ("APP PID {0} hwnd={1} vis={2}" -f $app.Id, $hwnd, [E1]::IsWindowVisible($hwnd))

$np = Start-Process 'C:\Windows\System32\notepad.exe' -PassThru
Start-Sleep -Seconds 2
[void][E1]::SetWindowPos($np.MainWindowHandle, [IntPtr]::Zero, 120, 120, 1000, 380, 0x0040)
Start-Sleep -Milliseconds 400
[void][E1]::SetForegroundWindow($np.MainWindowHandle)
Start-Sleep -Milliseconds 600
Set-Clipboard -Value 'hello world, this is a bubble translation test.'
(New-Object -ComObject WScript.Shell).SendKeys('^v')
Start-Sleep -Milliseconds 900

$pt = New-Object E1+POINT
[void][E1]::ClientToScreen($np.MainWindowHandle, [ref]$pt)
$startX = $pt.X + 45; $y = $pt.Y + 22
[void][E1]::SetCursorPos($startX, $y)
Start-Sleep -Milliseconds 300
[void][E1]::SetCursorPos(($startX + 6), $y)
Start-Sleep -Milliseconds 700
[E1]::mouse_event(0x0002,0,0,0,[IntPtr]::Zero)
Start-Sleep -Milliseconds 60
for ($i=1; $i -le 6; $i++) { [E1]::mouse_event(0x0001, 8, 0, 0, [IntPtr]::Zero); Start-Sleep -Milliseconds 45 }
[E1]::mouse_event(0x0004,0,0,0,[IntPtr]::Zero)
Start-Sleep -Milliseconds 900

# 气泡窗口（STranslate - Bubble 或匿名窗口）截图用整屏更稳
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap($b.Width,$b.Height)
$g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.Left,$b.Top,0,0,$bmp.Size); $g.Dispose()
$shot1 = 'D:\vibe_coding\english_learn\toolchain\e2e_bubble.png'
$bmp.Save($shot1, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
Write-Output ("bubble shot -> " + $shot1)

# 悬停气泡触发翻译
[void][E1]::SetCursorPos(($startX + 60), ($y + 34))
Start-Sleep -Seconds 5
Save-Bitmap $hwnd 'D:\vibe_coding\english_learn\toolchain\e2e_window.png'
Stop-Process -Id $np.Id -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 400

Write-Output '=== 新增日志关键行 ==='
$tail = Get-Content $log.FullName | Select-Object -Skip $base
$tail | Where-Object { $_ -match 'dictvoice|translate_tts|gettts|Audio|Speak|TTS|翻译|Caiyun|有道|bytes' } | Select-Object -First 40 | ForEach-Object { Write-Output $_ }
Write-Output ("=== 新增行数 {0} ===" -f $tail.Count)
