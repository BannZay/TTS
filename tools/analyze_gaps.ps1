# Reports silence start/end times in a recording. Usage: analyze_gaps.ps1 file.wav [-Db -45]
param([string]$File, [int]$Db=-45)
& ffmpeg -hide_banner -i $File -af "silencedetect=noise=${Db}dB:d=0.01" -f null - 2>&1 | Select-String 'silence_(start|end)' | % { "$_".Trim() -replace '^\[.*?\]\s*','' } | select -First 60
