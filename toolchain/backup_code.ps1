#requires -Version 7.0
# 源码备份：保留目录层级（Compress-Archive 传绝对路径会丢失层级，改用 ZipArchive 逐条写入）
param(
    [string]$Label = '代码快照',
    [string]$Root = 'D:\vibe_coding\english_learn'
)

Add-Type -AssemblyName System.IO.Compression.FileSystem

$dest = Join-Path $Root 'beifen'
New-Item -ItemType Directory -Force -Path $dest | Out-Null
$name = '{0}_{1}.zip' -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'), $Label
$target = Join-Path $dest $name

$skipDirs = @('node_modules', '.nuxt', '.output', '.temp', 'beifen', '__pycache__', '.venv',
              'dist', 'build', 'bin', 'obj', '.artifacts', 'toolchain', '.git')
$skipExt = @('.pyc', '.log', '.zip')

$files = Get-ChildItem -Path $Root -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
    $rel = $_.FullName.Substring($Root.Length).TrimStart('\')
    $parts = $rel -split '\\'
    $dirHit = $parts | Where-Object { $skipDirs -contains $_ }
    (-not $dirHit) -and ($skipExt -notcontains $_.Extension)
}
Write-Output ("FILES: {0}" -f $files.Count)

$zip = [System.IO.Compression.ZipFile]::Open($target, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($Root.Length).TrimStart('\')
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $zip, $f.FullName, $rel,
            [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
}
finally {
    $zip.Dispose()
}

$size = (Get-Item $target).Length
Write-Output ("BACKUP: {0}  SIZE: {1:N0} bytes  FILES: {2}" -f $target, $size, $files.Count)

# 自检：确认层级存在
$check = [System.IO.Compression.ZipFile]::OpenRead($target)
try {
    $entries = $check.Entries.Count
    $sample = ($check.Entries | Where-Object { $_.FullName -like '*STranslate/Services/VocabularyStore.cs' } | Select-Object -First 1)
    Write-Output ("ENTRIES: {0}  NESTED-SAMPLE: {1}" -f $entries, $(if ($sample) { $sample.FullName } else { 'MISSING' }))
}
finally {
    $check.Dispose()
}
