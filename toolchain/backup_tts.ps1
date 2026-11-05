#requires -Version 7.0
# 备份源码（排除依赖、构建产物、SDK 工具链、日志）
$root = 'D:\vibe_coding\english_learn'
$dest = Join-Path $root 'beifen'
New-Item -ItemType Directory -Force -Path $dest | Out-Null
$name = '{0}_生词本交互修正前.zip' -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')
$target = Join-Path $dest $name

$skip = '\\(node_modules|\.nuxt|\.output|\.temp|beifen|__pycache__|\.venv|dist|build|bin|obj|\.artifacts|toolchain|\.git)\\'
$files = Get-ChildItem -Path $root -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch $skip -and $_.Extension -notin '.pyc', '.log', '.zip' }

Compress-Archive -Path $files.FullName -DestinationPath $target -CompressionLevel Optimal
$size = (Get-Item $target).Length
Write-Output ("BACKUP: {0}  SIZE: {1:N0} bytes  FILES: {2}" -f $target, $size, $files.Count)
