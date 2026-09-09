param([string]$ImagePath)
Add-Type -AssemblyName System.Runtime.WindowsRuntime

function Await($task) { $task.GetAwaiter().GetResult() }

$null = [Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime]
$null = [Windows.Media.Ocr.OcrEngine,Windows.Foundation,ContentType=WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder,Windows.Graphics,ContentType=WindowsRuntime]

try {
  $file    = Await([Windows.Storage.StorageFile]::GetFileFromPathAsync($ImagePath))
  $stream  = Await($file.OpenAsync([Windows.Storage.FileAccessMode]::Read))
  $decoder = Await([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream))
  $bitmap  = Await($decoder.GetSoftwareBitmapAsync())
  $engine  = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
  if ($engine -eq $null) {
    $lang   = New-Object Windows.Globalization.Language("en-US")
    $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($lang)
  }
  $ocrResult = Await($engine.RecognizeAsync($bitmap))
  $ocrResult.Lines | ForEach-Object { $_.Text }
} catch {
  Write-Error $_.Exception.Message
  exit 1
}
