# Copies LibTTS-1.0 and LibStub from the submodule into the Libs folder of every addon that embeds them.
# Run after changing the library or moving the submodule to another commit.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $root 'LibTTS-1.0\LibTTS-1.0.lua'))) { throw 'Submodule missing: git submodule update --init' }
foreach ($addon in 'TTS', 'TTS_Diphone') {
    $lib = Join-Path $root "$addon\Libs\LibTTS-1.0"
    $stub = Join-Path $root "$addon\Libs\LibStub"
    New-Item -ItemType Directory -Force $lib, $stub | Out-Null
    Copy-Item (Join-Path $root 'LibTTS-1.0\LibTTS-1.0.lua'), (Join-Path $root 'LibTTS-1.0\LibTTS-1.0.xml') $lib
    Copy-Item (Join-Path $root 'LibTTS-1.0\LibStub\LibStub.lua') $stub
}
