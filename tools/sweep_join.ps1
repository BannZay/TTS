# Sweeps Core.JOIN_WEIGHT / RHYTHM_WEIGHT: renders common words with the Arctic voice and counts how many Windows speech
# recognition gets right (noisy, only relative). Usage: sweep_join.ps1 [-N 80] [-HQ]
param([int]$N=80, [switch]$HQ, [string]$Out="$env:TEMP\vc_sweep")
$ErrorActionPreference='Stop'
$root = Split-Path $PSScriptRoot -Parent
New-Item -ItemType Directory -Force $Out | Out-Null
Add-Type -AssemblyName System.Speech
Add-Type -TypeDefinition @"
using System; using System.IO;
public static class Mix3 {
  public static void Render(string[] clips, double[] starts, string outPath, int sr) {
    double end = 0; var data = new short[clips.Length][];
    for (int i = 0; i < clips.Length; i++) { var b = File.ReadAllBytes(clips[i]); var s = new short[(b.Length - 44) / 2]; Buffer.BlockCopy(b, 44, s, 0, s.Length * 2); data[i] = s; end = Math.Max(end, starts[i] + s.Length / (double)sr); }
    int pad = (int)(0.3 * sr); var mix = new double[(int)(end * sr) + 2 * pad];
    for (int i = 0; i < clips.Length; i++) { int o = pad + (int)Math.Round(starts[i] * sr); for (int k = 0; k < data[i].Length; k++) mix[o + k] += data[i][k]; }
    using (var w = new BinaryWriter(File.Create(outPath))) { int len = mix.Length * 2;
      w.Write(new char[] {'R','I','F','F'}); w.Write(36 + len); w.Write(new char[] {'W','A','V','E','f','m','t',' '});
      w.Write(16); w.Write((short)1); w.Write((short)1); w.Write(sr); w.Write(sr * 2); w.Write((short)2); w.Write((short)16);
      w.Write(new char[] {'d','a','t','a'}); w.Write(len);
      foreach (var v in mix) w.Write((short)Math.Max(-32768, Math.Min(32767, v))); }
  }
}
"@
# words: ranks 100..~3000 of the frequency list that the addon knows, 4+ letters, evenly spread
$known = @{}; foreach($l in Get-Content (Join-Path $root 'TTS_Diphone\Words.lua')){ if($l -match '^\["([a-z]+)"\]='){ $known[$matches[1]] = 1 } }
$cand = Get-Content (Join-Path $root 'tools\data\20k.txt') | Select -Skip 100 -First 3000 | ? { $_.Length -ge 4 -and $known.ContainsKey($_) }
$step = [math]::Max(1,[int]($cand.Count / $N)); $words = for($i=0;$i -lt $cand.Count -and $words.Count -lt $N;$i+=$step){ $cand[$i] }
$words = @($cand | % -Begin {$i=0} -Process { if($i % $step -eq 0){ $_ }; $i++ } | Select -First $N)
$tmp = Join-Path $env:TEMP 'vc_phrase'; New-Item -ItemType Directory -Force $tmp | Out-Null
$rec = New-Object System.Speech.Recognition.SpeechRecognitionEngine
$rec.LoadGrammar((New-Object System.Speech.Recognition.DictationGrammar)); $rec.InitialSilenceTimeout=[TimeSpan]::FromSeconds(3); $rec.EndSilenceTimeout=[TimeSpan]::FromSeconds(1)
$settings = @(@(0.04,1), @(0,1), @(0.02,1), @(0.08,1), @(0.16,1), @(0.04,0.5), @(0.04,2), @(0.08,0.5))
Push-Location (Join-Path $root 'tests')
foreach($st in $settings){
  $env:VC_JOIN = "$($st[0])"; $env:VC_RHYTHM = "$($st[1])"; $ok = 0; $conf = 0.0
  foreach($w in $words){
    $plan = & lua render_plan.lua $w arctic $(if($HQ){'hq'}else{'x'})
    $clips=@(); $starts=@(); $t=0.0
    foreach($l in $plan){ $pth,$d = $l -split "`t"; $rel = $pth -replace '^Interface\\AddOns\\',''; $k = ($rel -replace '[\\.]','_'); $cw = Join-Path $tmp "$k.wav"
      if(-not (Test-Path $cw)){ & ffmpeg -y -loglevel error -i (Join-Path $root $rel) -ar 16000 -ac 1 -map_metadata -1 -fflags +bitexact $cw }
      $clips += $cw; $starts += $t; $t += [double]$d }
    $wav = Join-Path $Out 'w.wav'; [Mix3]::Render([string[]]$clips, [double[]]$starts, $wav, 16000)
    $rec.SetInputToWaveFile($wav); $r = $rec.Recognize(); $rec.SetInputToNull()
    if($r -and $r.Text.ToLower() -eq $w){ $ok++ }; if($r){ $conf += $r.Confidence } }
  "join=$($st[0]) rhythm=$($st[1]): $ok/$($words.Count) exact, mean conf $([math]::Round($conf/$words.Count,3))" }
Pop-Location

