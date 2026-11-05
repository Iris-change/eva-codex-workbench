param([switch]$DesktopBoot,[ValidateRange(1024,65535)][int]$Port=43137,[switch]$NoBrowser)
$ErrorActionPreference = 'Stop'
$env:HACKCLAW_PORT=[string]$Port
$env:HACKCLAW_DATA_DIR=Join-Path $PSScriptRoot 'data'
$projectRoot = $PSScriptRoot
$url = 'http://127.0.0.1:'+$Port
$running = $false
try {
    $health = Invoke-RestMethod -Uri "$url/health" -TimeoutSec 2
    if ($health.app -ne 'EVA-UNIT02') { throw "Port $Port is occupied by another program." }
    $running = $true
} catch {
    if ($_.Exception.Message -like '*occupied*') { throw }
}
if (-not $running) {
    $nodePath = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe'
    if (-not (Test-Path -LiteralPath $nodePath)) { $nodePath = (Get-Command node -ErrorAction Stop).Source }
    & $nodePath -e "try{require(require.resolve('node-pty',{paths:[process.argv[1]]}));require.resolve('@xterm/xterm',{paths:[process.argv[1]]});require.resolve('@xterm/addon-fit',{paths:[process.argv[1]]})}catch{process.exit(1)}" $projectRoot
    if($LASTEXITCODE -ne 0){throw 'Missing terminal dependencies. Open a terminal in workbench and run: npm ci'}
    $env:HACKCLAW_CODEX = (Get-Command codex -ErrorAction Stop).Source
    $logDir = Join-Path $projectRoot 'data'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    Start-Process -FilePath $nodePath -ArgumentList ('"' + (Join-Path $projectRoot 'server.cjs') + '"') -WorkingDirectory $projectRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logDir 'server.log') -RedirectStandardError (Join-Path $logDir 'server-error.log')
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        Start-Sleep -Milliseconds 300
        try { $health = Invoke-RestMethod -Uri "$url/health" -TimeoutSec 1; if ($health.app -eq 'EVA-UNIT02') { $running = $true; break } } catch {}
    }
    if (-not $running) { throw 'Workbench could not start. See workbench/data/server-error.log.' }
}
if($NoBrowser){Write-Output "Workbench ready at $url";return}
$edgePath = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
if (Test-Path -LiteralPath $edgePath) {
    $profilePath = Join-Path $projectRoot 'data\unit02-browser'
    if ($DesktopBoot) {
        $launchUrl = $url + '/?boot=interactive&launch=' + [Guid]::NewGuid().ToString('N')
        Start-Process -FilePath $edgePath -ArgumentList ('--app=' + $launchUrl),('--user-data-dir="' + $profilePath + '"'),'--autoplay-policy=no-user-gesture-required','--no-first-run','--no-default-browser-check','--window-size=1500,950'
        return
    }
    # This is the visible, interactive workbench window requested by the user.
    $launchUrl = $url + '/?launch=' + [Guid]::NewGuid().ToString('N')
    Start-Process -FilePath $edgePath -ArgumentList ('--app=' + $launchUrl),('--user-data-dir="' + $profilePath + '"'),'--no-first-run','--no-default-browser-check','--window-size=1500,950'
} else {
    throw 'Microsoft Edge is required for the isolated UNIT-02 browser profile. Install Edge, then run this launcher again.'
}
