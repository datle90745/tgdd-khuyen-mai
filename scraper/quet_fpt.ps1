# Direct FPT production catalog scan on this Windows machine.
param([string]$Out = "$PSScriptRoot\..\data\fpt.js")
$ErrorActionPreference = 'Stop'
$node = (Get-Command node -ErrorAction Stop).Source
& $node (Join-Path $PSScriptRoot 'scan_fpt_local.mjs') --fpt-js $Out
if ($LASTEXITCODE -ne 0) { throw "FPT live scan failed ($LASTEXITCODE)" }
