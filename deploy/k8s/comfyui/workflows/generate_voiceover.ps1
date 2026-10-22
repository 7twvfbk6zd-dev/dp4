param(
    [string]$Storyboard = "",
    [string]$OutputDir = "",
    [string]$Voice = "Microsoft Huihui Desktop",
    [int]$DialogueRate = -2,
    [int]$CaptionRate = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Speech

if (-not $Storyboard) {
    $Storyboard = Join-Path $PSScriptRoot "storyboard.example.json"
}
if (-not $OutputDir) {
    $OutputDir = Join-Path (Get-Location) "outputs\comfyui\storyboard_demo_v3\audio"
}
if (-not (Test-Path -LiteralPath $Storyboard)) {
    throw "Storyboard not found: $Storyboard"
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$storyboardData = Get-Content -LiteralPath $Storyboard -Raw -Encoding UTF8 | ConvertFrom-Json
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
$voices = @($synth.GetInstalledVoices() | Where-Object { $_.Enabled })
$selected = $voices | Where-Object { $_.VoiceInfo.Name -eq $Voice } | Select-Object -First 1
if (-not $selected) {
    $selected = $voices | Where-Object { $_.VoiceInfo.Culture.Name -like "zh-*" } | Select-Object -First 1
}
if (-not $selected) {
    throw "No Chinese speech voice is installed"
}
$synth.SelectVoice($selected.VoiceInfo.Name)

$format = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(
    16000,
    [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen,
    [System.Speech.AudioFormat.AudioChannel]::Mono
)
$entries = New-Object System.Collections.Generic.List[object]

foreach ($panel in $storyboardData.panels) {
    $lines = @()
    if ($panel.PSObject.Properties.Name -contains "caption" -and $panel.caption) {
        $lines += [pscustomobject]@{ Type = "caption"; Text = $panel.caption; Rate = $CaptionRate }
    }
    if ($panel.PSObject.Properties.Name -contains "dialogue" -and $panel.dialogue) {
        $lines += [pscustomobject]@{ Type = "dialogue"; Text = $panel.dialogue; Rate = $DialogueRate }
    }

    foreach ($line in $lines) {
        $suffix = if ($lines.Count -gt 1) { "_$($line.Type)" } else { "" }
        $fileName = "$($panel.name)$suffix.wav"
        $filePath = Join-Path $OutputDir $fileName
        $synth.Rate = [int]$line.Rate
        $synth.SetOutputToWaveFile($filePath, $format)
        $synth.Speak($line.Text)
        $synth.SetOutputToNull()
        $entries.Add([pscustomobject]@{
            panel = $panel.name
            type = $line.Type
            text = $line.Text
            file = $fileName
            rate = $line.Rate
        })
        Write-Host "wrote $filePath"
    }
}

$synth.SetOutputToNull()
$synth.Dispose()
$json = $entries | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText(
    (Join-Path $OutputDir "voiceover.json"),
    $json,
    (New-Object System.Text.UTF8Encoding($false))
)
Write-Host "voice: $($selected.VoiceInfo.Name)"
Write-Host "clips: $($entries.Count) in $OutputDir"
