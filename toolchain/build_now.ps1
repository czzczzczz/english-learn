#requires -Version 7.0
$root = 'D:\vibe_coding\english_learn'
$env:DOTNET_CLI_HOME = Join-Path $root 'toolchain\home'
$env:NUGET_PACKAGES = Join-Path $root 'toolchain\nuget'
$tmp = Join-Path $root 'toolchain\tmp'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$env:TEMP = $tmp
$env:TMP = $tmp
Set-Location (Join-Path $root 'vendor\STranslate-main\src')
& (Join-Path $root 'toolchain\dotnet\dotnet.exe') build STranslate.slnx -c Debug --nologo -v:m 2>&1 | Where-Object { $_ -match 'error|已成功生成|个错误|个警告' } | Select-Object -Last 20
"EXITCODE=$LASTEXITCODE"
