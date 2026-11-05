Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class Tok {
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool OpenProcessToken(IntPtr h, uint a, out IntPtr t);
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool GetTokenInformation(IntPtr t, int c, IntPtr i, int l, out int r);
  [DllImport("advapi32.dll")] static extern IntPtr GetSidSubAuthority(IntPtr sid, uint index);
  [DllImport("advapi32.dll")] static extern IntPtr GetSidSubAuthorityCount(IntPtr sid);
  public static int Level(IntPtr proc) {
    IntPtr tok;
    if (!OpenProcessToken(proc, 0x0008, out tok)) return -1;
    int len;
    GetTokenInformation(tok, 25, IntPtr.Zero, 0, out len);
    IntPtr buf = Marshal.AllocHGlobal(len);
    if (!GetTokenInformation(tok, 25, buf, len, out len)) { Marshal.FreeHGlobal(buf); return -2; }
    IntPtr sid = Marshal.ReadIntPtr(buf);
    byte cnt = Marshal.ReadByte(GetSidSubAuthorityCount(sid));
    IntPtr sub = GetSidSubAuthority(sid, (uint)(cnt - 1));
    int lvl = Marshal.ReadInt32(sub);
    Marshal.FreeHGlobal(buf);
    return lvl;
  }
}
"@

$p = Get-Process -Name $args[0] -ErrorAction SilentlyContinue | Select-Object -First 1
if ($p) { "app IL = 0x{0:X}" -f [Tok]::Level($p.Handle) } else { "app not running" }
"self IL = 0x{0:X}" -f [Tok]::Level((Get-Process -Id $PID).Handle)
