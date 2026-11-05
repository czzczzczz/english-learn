# 打开设置 → 语音合成 → 点击服务行，看设置面板是否出现
Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class SvcTest {
  public delegate bool EP(IntPtr h, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint a,uint b,uint c,IntPtr e);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  public const uint LD=0x0002, LU=0x0004;
  public static IntPtr Find(uint pid,string t){ IntPtr f=IntPtr.Zero; EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid){var sb=new StringBuilder(256); GetWindowText(h,sb,256); if(sb.ToString()==t){f=h;return false;}} return true;}, IntPtr.Zero); return f;}
  public static void Click(int x,int y){ SetCursorPos(x,y); System.Threading.Thread.Sleep(150); mouse_event(LD,0,0,0,IntPtr.Zero); mouse_event(LU,0,0,0,IntPtr.Zero); }
}
"@
$p = Get-Process STranslate
$h = [SvcTest]::Find([uint32]$p.Id, "设置")
if ($h -eq [IntPtr]::Zero) { Write-Host "settings window not found"; exit }
[void][SvcTest]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 400
$r = New-Object SvcTest+RECT; [void][SvcTest]::GetWindowRect($h, [ref]$r)
$w = $r.R - $r.L; $ht = $r.B - $r.T
Write-Host "settings rect=$($r.L),$($r.T) size=${w}x${ht}"

# 左侧导航「语音合成」：按比例定位
[SvcTest]::Click(($r.L + 95), ($r.T + 302))
Start-Sleep -Milliseconds 700

# 服务行（Baidu TTS）
[SvcTest]::Click(($r.L + 396), ($r.T + 135))
Start-Sleep -Milliseconds 800

Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap($w, $ht)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size); $g.Dispose()
$bmp.Save("D:\vibe_coding\english_learn\toolchain\tts_settings.png")
$bmp.Dispose()
Write-Host "saved"
