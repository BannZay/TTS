# Builds the diphone clips from Festival's kal_diphone voice (a real recorded diphone database, monotone pitch,
# fixed durations), via WSL (see tools/festival/setup.sh). Writes the same outputs as generate_diphones.ps1:
# TTS_Diphone/diphones/*.ogg, Words.lua (word -> phoneme string), Diphones.lua (key -> seconds).
param([int]$MaxWords=1000000, [double]$Ov=0, [switch]$Snap, [int]$Quality=3, [int]$Threads=4, [string]$WordFile='', [string]$Stage='')   # Stage: write the addon data to this folder instead of TTS\
$ErrorActionPreference='Stop'
$root = Split-Path $PSScriptRoot -Parent
$dest = if($Stage){ $Stage } else { Join-Path $root 'TTS_Diphone' }
$out  = Join-Path $dest 'diphones'
$fw   = Join-Path $PSScriptRoot 'festival\work'
$cut  = Join-Path $env:TEMP 'vc_fest_cut'
Remove-Item $fw,$cut -Recurse -Force -ea 0
New-Item -ItemType Directory -Force $out,"$fw\wav",$cut | Out-Null
$cs = @'
using System; using System.Diagnostics; using System.IO; using System.Threading.Tasks;
public static class Cutter {
  public static string Q = "3";
  // Cuts [t0,t1] out of a 16-bit mono wav with linear fades; returns written length in seconds (0 if too short).
  static int Snap(short[] x, int i, int sr) { int best = i, bd = int.MaxValue, r = (int)(0.005 * sr); for (int k = Math.Max(1, i - r); k < Math.Min(x.Length, i + r); k++) if (x[k-1] < 0 && x[k] >= 0 && Math.Abs(k - i) < bd) { bd = Math.Abs(k - i); best = k; } return best; }
  public static double Cut(string src, string dst, double t0, double t1, double fadeIn, double fadeOut, bool snapL, bool snapR, bool trimL, bool trimR) {
    var b = File.ReadAllBytes(src);
    int sr = BitConverter.ToInt32(b, 24), dataPos = 12;
    while (dataPos + 8 < b.Length && !(b[dataPos]=='d' && b[dataPos+1]=='a' && b[dataPos+2]=='t' && b[dataPos+3]=='a')) dataPos += 8 + BitConverter.ToInt32(b, dataPos + 4);
    dataPos += 8;
    int total = (b.Length - dataPos) / 2; var all = new short[total]; Buffer.BlockCopy(b, dataPos, all, 0, total * 2);
    int a = Math.Max(0, (int)Math.Round(t0 * sr)), e = Math.Min(total, (int)Math.Round(t1 * sr));
    if (snapL) a = Snap(all, a, sr); if (snapR) e = Snap(all, e, sr); if (trimL) while (a < e - 1 && Math.Abs((int)all[a]) < 150) a++; if (trimR) while (e > a + 1 && Math.Abs((int)all[e - 1]) < 150) e--; int n = e - a;
    if (n < sr * 0.004) return 0;
    var seg = new short[n]; int fi = Math.Max(1, (int)(fadeIn * sr)), fo = Math.Max(1, (int)(fadeOut * sr));
    for (int i = 0; i < n; i++) { double g = 1; if (i < fi) g = i / (double)fi; if (n - 1 - i < fo) g = Math.Min(g, (n - 1 - i) / (double)fo); seg[i] = (short)(all[a + i] * g); }
    using (var w = new BinaryWriter(File.Create(dst))) {
      int len = n * 2; w.Write(new char[] {'R','I','F','F'}); w.Write(36 + len); w.Write(new char[] {'W','A','V','E','f','m','t',' '});
      w.Write(16); w.Write((short)1); w.Write((short)1); w.Write(sr); w.Write(sr * 2); w.Write((short)2); w.Write((short)16);
      w.Write(new char[] {'d','a','t','a'}); w.Write(len); var bb = new byte[len]; Buffer.BlockCopy(seg, 0, bb, 0, len); w.Write(bb); }
    return n / (double)sr;
  }
  public static void EncodeAll(string[] wavs, string outDir, int threads) {
    Parallel.ForEach(wavs, new ParallelOptions { MaxDegreeOfParallelism = threads }, wav => {
      var psi = new ProcessStartInfo("ffmpeg", "-y -loglevel error -i \"" + wav + "\" -ac 1 -c:a libvorbis -q:a " + Q + " \"" + Path.Combine(outDir, Path.GetFileNameWithoutExtension(wav) + ".ogg") + "\"");
      psi.UseShellExecute = false; psi.CreateNoWindow = true;
      using (var p = Process.Start(psi)) p.WaitForExit();
    });
  }
}
'@
Add-Type -TypeDefinition $cs
$inv = [Globalization.CultureInfo]::InvariantCulture
# index order defines the phoneme codes (0 = silence); value = Festival radio phoneset name. Must match generate_diphones.ps1.
$ph = [ordered]@{ AA='aa';AE='ae';AH0='ax';AH='ah';AO='ao';AW='aw';AY='ay';B='b';CH='ch';D='d';DH='dh';EH='eh';ER='er';EY='ey';F='f';G='g';HH='hh';IH='ih';IY='iy';JH='jh';K='k';L='l';M='m';N='n';NG='ng';OW='ow';OY='oy';P='p';R='r';S='s';SH='sh';T='t';TH='th';UH='uh';UW='uw';V='v';W='w';Y='y';Z='z';ZH='zh' }
$names = @($ph.Keys); $idx=@{}; for($i=0;$i -lt $names.Count;$i++){ $idx[$names[$i]] = $i+1 }
function Code($n){ [string][char](48+$n) }
# phone with CMU stress digit -> code char, preceded by ^ (primary) or ~ (secondary stress) for vowels
function CodeS($p){ $b = Norm $p; $mk = ''; if($b -ne 'AH0' -and $p -match '1$'){ $mk = '^' } elseif($b -ne 'AH0' -and $p -match '2$'){ $mk = '~' }; return $mk + (Code $idx[$b]) }
function Norm($p){ if($p -eq 'AH0'){return 'AH0'}; return ($p -replace '\d','') }

$freq = if($WordFile){ Get-Content $WordFile } else { Get-Content (Join-Path $PSScriptRoot 'data\20k.txt') }
$dict=@{}
foreach($ln in Get-Content (Join-Path $PSScriptRoot 'data\cmudict.dict')){
  $p=($ln -replace '\s+#.*$','') -split ' '
  if($p[0] -match "^[a-z']+$" -and -not $dict.ContainsKey($p[0])){ $dict[$p[0]] = $p[1..($p.Length-1)] } }
$words = New-Object Collections.Generic.List[object]; $pairs=@{}
# common words first (so -MaxWords keeps them), then the rest of the dictionary
$order = @($freq) + @($dict.PSBase.Keys | Sort-Object)   # PSBase: the dictionary has words named "keys" and "count"
$seen=@{}
foreach($w in $order){
  if($seen.ContainsKey($w)){continue}; $seen[$w]=1
  if($words.Count -ge $MaxWords){break}
  if(-not $dict.ContainsKey($w)){continue}
  $mid = @($dict[$w] | % { $n=Norm $_; if(-not $idx.ContainsKey($n)){throw "unknown phone $n ($w)"}; $idx[$n] })
  $seq = @(0) + $mid + @(0)
  $words.Add(@($w, (($dict[$w] | % { CodeS $_ }) -join '')))
  for($i=0;$i -lt $seq.Length-1;$i++){ $pairs[("{0:00}{1:00}" -f $seq[$i],$seq[$i+1])] = 1 } }
# every pair of phonemes (not just those in the dictionary), so letter-to-sound guesses never hit a missing diphone
for($a=0;$a -le $names.Count;$a++){ for($b=0;$b -le $names.Count;$b++){ if($a -ne 0 -or $b -ne 0){ $pairs[("{0:00}{1:00}" -f $a,$b)] = 1 } } }
$todo = @($pairs.PSBase.Keys | Sort-Object)
"words=$($words.Count) diphones=$($todo.Count)"

# --- request file for Festival: ("key" (pau a b pau)) per diphone
function FName($n){ if($n -eq 0){'pau'}else{ $ph[$names[$n-1]] } }
$req = foreach($key in $todo){
  $a=[int]$key.Substring(0,2); $b=[int]$key.Substring(2,2)
  $list = if($a -eq 0){ "pau $(FName $b) pau" } elseif($b -eq 0){ "pau $(FName $a) pau" } else { "pau $(FName $a) $(FName $b) pau" }
  "(`"$key`" ($list))" }
Set-Content "$fw\pairs.scm" ("(set! vc_pairs '(`n" + ($req -join "`n") + "`n))`n") -Encoding ascii
"running Festival (WSL)..."
# gen.scm holds @ROOT@ for the repository folder as WSL sees it
$wslRoot = '/mnt/' + $root.Substring(0,1).ToLower() + $root.Substring(2).Replace('\', '/')
[IO.File]::WriteAllText("$fw\gen.scm", [IO.File]::ReadAllText("$PSScriptRoot\festival\gen.scm").Replace('@ROOT@', $wslRoot))
$ErrorActionPreference='Continue'; $ends = & wsl -d Ubuntu -e sh "$wslRoot/tools/festival/run.sh" "$wslRoot/tools/festival/work/gen.scm" 2>$null; $ErrorActionPreference='Stop'
$endMap=@{}; foreach($l in $ends){ if($l -match '^(\d{5}) E \(([^)]*)\) S \(([^)]*)\) U \(([^)]*)\)'){ $endMap[$matches[1]] = @{ E=[double[]]($matches[2].Trim() -split ' '); S=[double[]]($matches[3].Trim() -split ' '); U=[double[]]($matches[4].Trim() -split ' ') } } }
"festival rendered $($endMap.Count) / $($todo.Count * 3)"

# --- cut: diphone boundaries are the unit joins of the diphone synthesizer. Unit ends are in source time; map them to
# --- output time with the piecewise-linear segment map (segment source_end -> end), as Festival's own time warping does.
function ToTarget($u, $E, $S){
  $s0 = 0.0; $e0 = 0.0
  for($j=0; $j -lt $S.Count; $j++){
    if($u -le $S[$j] -or $j -eq $S.Count-1){ return $e0 + ($u-$s0)/($S[$j]-$s0)*($E[$j]-$e0) }
    $s0 = $S[$j]; $e0 = $E[$j] } }
$dur=@{}; $failed=@()
foreach($base in $todo){ foreach($v in 1..3){
  $key = "$base$v"
  if(-not $endMap.ContainsKey($key)){ $failed += $key; continue }
  $m = $endMap[$key]; $E=$m.E; $S=$m.S; $U=$m.U
  $a=[int]$base.Substring(0,2); $b=[int]$base.Substring(2,2)
  $j = @($U | % { ToTarget $_ $E $S })       # output time of each unit's end (= the join with the next unit)
  if($a -eq 0){ $t0=0.0; $t1=$j[0]; $hardL=$true; $hardR=$false }                       # pau-X: from start (silence trimmed) to the join
  elseif($b -eq 0){ $t0=$j[0]; $t1=$E[$E.Count-1]; $hardL=$false; $hardR=$true }       # X-pau: from the join to the end (silence trimmed)
  else { $t0=$j[0]; $t1=$j[1]; $hardL=$false; $hardR=$false }
  $a0 = if($hardL){$t0}else{[math]::Max($t0-$Ov,0)}; $a1 = if($hardR){$t1}else{$t1+$Ov}
  $len = [Cutter]::Cut("$fw\wav\$key.wav", (Join-Path $cut "$key.wav"), $a0, $a1, $(if($hardL){0.003}else{$Ov}), $(if($hardR){0.003}else{$Ov}), (-not $hardL -and $Snap), (-not $hardR -and $Snap), $hardL, $hardR)
  # nominal (playback spacing) length excludes the overlap extensions
  $nominal = $len - $(if($hardL){0}else{$Ov}) - $(if($hardR){0}else{$Ov})
  if($len -gt 0 -and $nominal -gt 0.003){ $dur[$key] = $nominal } else { $failed += $key } } }
"failed: $($failed.Count) $(($failed | select -First 10) -join ',')"
Remove-Item (Join-Path $out '*.ogg') -ea 0
[Cutter]::Q = "$Quality"; [Cutter]::EncodeAll([string[]]@(Get-ChildItem $cut -Filter *.wav | % { $_.FullName }), $out, $Threads)

$wl = $words | % { '["{0}"]="{1}"' -f $_[0],$_[1] }
Set-Content (Join-Path $dest 'Words.lua') ("-- Generated by tools/generate_festival.ps1. word -> phoneme string (char = 48 + phoneme index)`nTTS_DiphoneWords = {`n" + ($wl -join ",`n") + "`n}`n") -Encoding ascii
$dl = $dur.PSBase.Keys | Sort-Object | % { '["{0}"]={1}' -f $_,$dur[$_].ToString('0.000',$inv) }
Set-Content (Join-Path $dest 'Diphones.lua') ("-- Generated. diphone key = two 2-digit phoneme indices + duration variant (1 short, 2 normal, 3 long) -> seconds`nTTS_Diphones = {`n" + ($dl -join ",`n") + "`n}`n") -Encoding ascii
"clips: $($dur.Count)"

# --- letter names for spelling (acronyms, words with no vowel)
$letterPh = [ordered]@{ a='EY1'; b='B IY1'; c='S IY1'; d='D IY1'; e='IY1'; f='EH1 F'; g='JH IY1'; h='EY1 CH'; i='AY1'; j='JH EY1'; k='K EY1'; l='EH1 L'; m='EH1 M'; n='EH1 N'; o='OW1'; p='P IY1'; q='K Y UW1'; r='AA1 R'; s='EH1 S'; t='T IY1'; u='Y UW1'; v='V IY1'; w='D AH1 B AH0 L Y UW0'; x='EH1 K S'; y='W AY1'; z='Z IY1' }
$ll = $letterPh.Keys | % { '{0}="{1}"' -f $_, ((($letterPh[$_] -split ' ') | % { CodeS $_ }) -join '') }
Set-Content (Join-Path $dest 'Letters.lua') ("-- Generated by tools/generate_festival.ps1. letter -> phoneme string (letter names)`nTTS_DiphoneLetters = {`n" + ($ll -join ",`n") + "`n}`n") -Encoding ascii
"letters: $($letterPh.Count)"