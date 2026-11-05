#requires -Version 7.0
# 备份脚本：改动前打包源码与配置，排除构建产物、工具链与日志
$ErrorActionPreference = 'Stop'
$root = 'D:\vibe_coding\english_learn'
$dest = Join-Path $root 'beifen'
New-Item -ItemType Directory -Force -Path $dest | Out-Null
$name = '{0}_日志降噪与残留清理.zip' -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')
$out = Join-Path $dest $name
$skipDir = '\\(\.artifacts|bin|obj|beifen|toolchain|\.git|\.vs)\\|\\packages\\'
$skipExt = @('.log', '.zip', '.pdb')
$files = Get-ChildItem -Path $root -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch $skipDir -and $_.Extension -notin $skipExt }
Write-Output ("files=" + $files.Count)
Compress-Archive -Path $files.FullName -DestinationPath $out -CompressionLevel Optimal
$info = Get-Item $out
Write-Output ("zip=" + $info.FullName)
Write-Output ("sizeMB=" + [math]::Round($info.Length / 1MB, 2))
