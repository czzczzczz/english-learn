#requires -Version 7.0
# 部署到 D:\vibe_coding\STranslate-dev（保留 PortableConfig），并启动
$src = 'D:\vibe_coding\english_learn\vendor\STranslate-main\src\.artifacts\Debug'
$dst = 'D:\vibe_coding\STranslate-dev'

Get-Process -Name 'STranslate' -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 800

$out = robocopy $src $dst /E /XD PortableConfig /NFL /NDL /NJH /NJS /NP
Write-Output ("ROBOCOPY EXIT: {0}" -f $LASTEXITCODE)

$env:TMP = 'D:\vibe_coding\english_learn\toolchain\tmp'
$env:TEMP = $env:TMP
New-Item -ItemType Directory -Force -Path $env:TMP | Out-Null
$p = Start-Process -FilePath (Join-Path $dst 'STranslate.exe') -PassThru
Start-Sleep -Seconds 6
Write-Output ("PID: {0}  RUNNING: {1}" -f $p.Id, (-not $p.HasExited))
