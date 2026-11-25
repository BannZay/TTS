# Offline intelligibility check: renders words from the diphone clips the way the addon plays them
# (nominal-length spacing, overlap), then runs Windows speech recognition on the result.
# Usage: assess_words.ps1 -Words hello,world,... [-Sentence "hello world"] [-Mode diphone|ref] [-Keep]
param([string[]]$Words=@('hello','world','how','are','you','today','good','morning','thank','please'), [string]$Mode='diphone', [string]$Dir="$env:TEMP\vc_assess", [double]$Ov=0.012)
$ErrorActionPreference='Stop'
$root = Split-Path $PSScriptRoot -Parent
New-Item -ItemType Directory -Force $Dir | Out-Null
Add-Type -AssemblyName System.Speech
$cs = @'
using System; using System.IO;
public static class Mix {
  const int SR = 22050;
  public static short[] Read(string path) { var b = File.ReadAllBytes(path); var s = new short[(b.Length - 44) / 2]; Buffer.BlockCopy(b, 44, s, 0, s.Length * 2); return s; }
  public static void Write(string path, double[] mix) {
    int n = mix.Length; using (var w = new BinaryWriter(File.Create(path))) {
      int len = n * 2; w.Write(new char[] {'R','I','F','F'}); w.Write(36 + len); w.Write(new char[] {'W','A','V','E','f','m','t',' '});
      w.Write(16); w.Write((short)1); w.Write((short)1); w.Write(SR); w.Write(SR * 2); w.Write((short)2); w.Write((short)16);
      w.Write(new char[] {'d','a','t','a'}); w.Write(len);
      for (int i = 0; i < n; i++) w.Write((short)Math.Max(-32768, Math.Min(32767, mix[i]))); } }
  // clips[i] placed at starts[i] seconds; padded with 0.4 s of silence on both sides
  public static void Render(string[] clips, double[] starts, string outPath) {
    double end = 0; var data = new short[clips.Length][];
    for (int i = 0; i < clips.Length; i++) { data[i] = Read(clips[i]); end = Math.Max(end, starts[i] + data[i].Length / (double)SR); }
    int pad = (int)(0.4 * SR); var mix = new double[(int)(end * SR) + 2 * pad];
    for (int i = 0; i < clips.Length; i++) { int o = pad + (int)Math.Round(starts[i] * SR); for (int k = 0; k < data[i].Length; k++) mix[o + k] += data[i][k]; }
    Write(outPath, mix);
  }
}
'@
Add-Type -TypeDefinition $cs
$tmp = Join-Path $Dir 'clips'; New-Item -ItemType Directory -Force $tmp | Out-Null; Get-ChildItem $tmp -Filter *.wav | Remove-Item
$ov = $Ov
$ph = @{}; foreach($l in Get-Content (Join-Path $root 'TTS_Diphone\Words.lua')){ if($l -match '^\["([a-z]+)"\]="(.*)"'){ $ph[$matches[1]] = $matches[2] } }
$dur = @{}; foreach($l in Get-Content (Join-Path $root 'TTS\Diphones.lua')){ if($l -match '^\["(\d+)"\]=([\d.]+)'){ $dur[$matches[1]] = [double]$matches[2] } }
$rec = New-Object System.Speech.Recognition.SpeechRecognitionEngine
$rec.LoadGrammar((New-Object System.Speech.Recognition.DictationGrammar))
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer; $synth.SelectVoice('Microsoft Zira Desktop')
$ok = 0
foreach($w in $Words){
  $wav = Join-Path $Dir "$w.wav"
  if($Mode -eq 'ref'){ $synth.SetOutputToWaveFile($wav); $synth.Speak($w); $synth.SetOutputToNull() }
  elseif($Mode -eq 'fest'){ Copy-Item "$PSScriptRoot\festival\work\ref_$w.wav" $wav -Force }
  elseif($Mode -eq 'ipa'){   # whole word synthesized from its phoneme string in one utterance (tests the phoneme source itself)
    $ipaMap = @('ɑ','æ','ə','ʌ','ɔ','aʊ','aɪ','b','tʃ','d','ð','ɛ','ɝ','eɪ','f','ɡ','h','ɪ','i','dʒ','k','l','m','n','ŋ','oʊ','ɔɪ','p','ɹ','s','ʃ','t','θ','ʊ','u','v','w','j','z','ʒ')
    $ipa = -join ($ph[$w].ToCharArray() | % { $ipaMap[[int][char]$_ - 49] })
    $synth.SetOutputToWaveFile($wav)
    $synth.SpeakSsml("<speak version='1.0' xml:lang='en-US' xmlns='http://www.w3.org/2001/10/synthesis'><phoneme alphabet='ipa' ph='$ipa'>x</phoneme></speak>")
    $synth.SetOutputToNull()
  }
  else {
    $p = $ph[$w]; if(-not $p){ "$w : not in dictionary"; continue }
    $clips=@(); $starts=@(); $t=0.0; $prev=0
    for($i=0;$i -le $p.Length;$i++){
      $cur = if($i -lt $p.Length){ [int][char]$p[$i] - 48 } else { 0 }
      $key = "{0:00}{1:00}" -f $prev,$cur
      if($dur.ContainsKey($key)){
        $eL = if($prev -eq 0){0}else{$ov}
        $cw = Join-Path $tmp "$key.wav"; if(-not (Test-Path $cw)){ & ffmpeg -y -loglevel error -i (Join-Path $root "TTS\diphones\$key.ogg") -ar 22050 -ac 1 -map_metadata -1 -fflags +bitexact $cw }; $clips += $cw; $starts += ($t - $eL); $t += $dur[$key] }
      $prev = $cur }
    [Mix]::Render([string[]]$clips, [double[]]$starts, $wav)
  }
  $rec.SetInputToWaveFile($wav)
  $r = $rec.Recognize()
  $got = if($r){ "$($r.Text) ($([math]::Round($r.Confidence,2)))" } else { '<nothing>' }
  if($r -and $r.Text.ToLower() -eq $w){ $ok++ }
  '{0,-10} -> {1}' -f $w,$got
}
"correct: $ok / $($Words.Count)  [$Mode]"
