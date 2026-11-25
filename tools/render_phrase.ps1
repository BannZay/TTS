# Renders a phrase the way the addon plays it (same plan, same spacing) into a wav, for listening.
# Usage: render_phrase.ps1 "some text" out.wav
param([string]$Text, [string]$Out, [string]$Voice='kal', [switch]$HQ)
$ErrorActionPreference='Stop'
$root = Split-Path $PSScriptRoot -Parent
Add-Type -TypeDefinition @"
using System; using System.IO;
public static class Mix2 {
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
$tmp = Join-Path $env:TEMP 'vc_phrase'; New-Item -ItemType Directory -Force $tmp | Out-Null
Push-Location (Join-Path $root 'tests')
$plan = & lua render_plan.lua $Text $Voice $(if($HQ){'hq'}else{'x'})
Pop-Location
$clips=@(); $starts=@(); $t=0.0
foreach($l in $plan){ $pth,$w = $l -split "`t"; $rel = $pth -replace '^Interface\\AddOns\\',''; $k = ($rel -replace '[\\.]','_') + '_' + (Get-Item (Join-Path $root $rel)).LastWriteTimeUtc.Ticks; $cw = Join-Path $tmp "$k.wav"
  if(-not (Test-Path $cw)){ & ffmpeg -y -loglevel error -i (Join-Path $root $rel) -ar 16000 -ac 1 -map_metadata -1 -fflags +bitexact $cw }
  $clips += $cw; $starts += $t; $t += [double]$w }
[Mix2]::Render([string[]]$clips, [double[]]$starts, $Out, 16000)
"wrote $Out ($($clips.Count) clips, $([math]::Round($t,1)) s)"
