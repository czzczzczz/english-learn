# 用 Windows 内置 OCR（Windows.Media.Ocr）识别一张英文图片，验证可用性
# 需用 Windows PowerShell 5.1 运行（WinRT 投影）
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$tmp = 'D:\dsh\cache\tmp\ocr-test'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$imgPath = Join-Path $tmp 'en-sample.png'

# 生成一张带英文的图片
$bmp = [System.Drawing.Bitmap]::new(900, 220)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::White)
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$font = [System.Drawing.Font]::new("Segoe UI", 20)
$brush = [System.Drawing.Brushes]::Black
$g.DrawString('Learning English is easier', $font, $brush, 20, 30)
$g.DrawString('when you listen every day.', $font, $brush, 20, 80)
$g.DrawString('campaign  transcription  vocabulary', $font, $brush, 20, 140)
$g.Dispose()
$bmp.Save($imgPath, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output ("image: " + $imgPath)

# WinRT 异步等待 helper
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
})[0]

function Await($op, $resultType) {
    $asTask = $asTaskGeneric.MakeGenericMethod($resultType)
    $task = $asTask.Invoke($null, @($op))
    $task.Wait(-1) | Out-Null
    $task.Result
}

[Windows.Storage.StorageFile, Windows.Storage, ContentType=WindowsRuntime] | Out-Null
[Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics, ContentType=WindowsRuntime] | Out-Null
[Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType=WindowsRuntime] | Out-Null

$file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($imgPath)) ([Windows.Storage.StorageFile])
$stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
$decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
$bitmap = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])

foreach ($lang in [Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages) {
    $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($lang)
    if ($null -eq $engine) { Write-Output ("engine null for " + $lang.LanguageTag); continue }
    $result = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
    Write-Output ("=== LANG " + $lang.LanguageTag + " ===")
    Write-Output $result.Text
}
