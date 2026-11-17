# Downloads the latest Node.js LTS (win-x64) and extracts node.exe to windows\bin\node.exe,
# verifying the SHA-256 published by nodejs.org. Used by the release build (CI) before ISCC.
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = "SilentlyContinue"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$binDir = Join-Path (Split-Path -Parent $here) "bin"
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("aigauge_node_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp, $binDir -Force | Out-Null

try {
    $arch = "win-x64"
    $index = Invoke-RestMethod -Uri "https://nodejs.org/dist/index.json" -UseBasicParsing
    $rel = $index | Where-Object { $_.lts -and ($_.files -contains "$arch-zip") } | Select-Object -First 1
    if (-not $rel) { throw "No Node.js LTS release found for $arch" }
    $ver = $rel.version
    $zipName = "node-$ver-$arch.zip"
    $zipPath = Join-Path $tmp $zipName

    Invoke-WebRequest -Uri "https://nodejs.org/dist/$ver/$zipName" -OutFile $zipPath -UseBasicParsing
    $sums = (Invoke-WebRequest -Uri "https://nodejs.org/dist/$ver/SHASUMS256.txt" -UseBasicParsing).Content
    $line = ($sums -split "`n" | Where-Object { $_ -match [regex]::Escape($zipName) } | Select-Object -First 1)
    $expected = ($line -split "\s+")[0]
    $actual = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash
    if (-not $expected -or ($expected.ToLower() -ne $actual.ToLower())) { throw "SHA-256 mismatch for $zipName" }

    Expand-Archive -Path $zipPath -DestinationPath $tmp -Force
    Copy-Item -Path (Join-Path $tmp "node-$ver-$arch\node.exe") -Destination (Join-Path $binDir "node.exe") -Force
    Write-Host "Node.js $ver ($arch) ready at $binDir\node.exe"
} finally {
    Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
