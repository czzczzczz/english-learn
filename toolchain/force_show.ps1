$ErrorActionPreference = 'Stop'
Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class W3 {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  public static string[] List(uint pid) {
    var acc = new System.Collections.Generic.List<string>();
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid){ var sb=new StringBuilder(512); GetWindowText(h,sb,512); if(sb.Length>0) acc.Add("vis=" + IsWindowVisible(h) + " hwnd=" + h + " title='" + sb + "'"); } return true; }, IntPtr.Zero);
    return acc.ToArray();
  }
  public static IntPtr Find(uint pid, string title){
    IntPtr f=IntPtr.Zero;
    EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid){var sb=new StringBuilder(512); GetWindowText(h,sb,512); if(sb.ToString()==title){f=h;return false;}} return true;}, IntPtr.Zero);
    return f;
  }
}
"@
$p = Get-Process STranslate
[W3]::List([uint32]$p.Id) | ForEach-Object { Write-Output $_ }
$h = [W3]::Find([uint32]$p.Id, 'STranslate')
if ($h -ne [IntPtr]::Zero) {
  [void][W3]::ShowWindow($h, 5)
  [void][W3]::SetForegroundWindow($h)
  Start-Sleep -Milliseconds 800
  Write-Output ("after Show: vis=" + [W3]::IsWindowVisible($h))
} else { Write-Output 'no STranslate window' }
