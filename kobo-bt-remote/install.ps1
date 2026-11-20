# Installeert kobo.koplugin + de remote-setup-patch op een via USB verbonden Kobo (Windows).
#
#   powershell -ExecutionPolicy Bypass -File install.ps1          zoekt de Kobo en installeert
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Wait    wacht tot de Kobo verbonden is
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Drive E:
param(
    [string]$Drive = "",
    [switch]$Wait
)
$ErrorActionPreference = "Stop"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Payload = Join-Path $Here "payload\koreader"

function Find-Kobo {
    foreach ($d in (Get-PSDrive -PSProvider FileSystem)) {
        $root = $d.Root
        if (Test-Path (Join-Path $root ".kobo\version")) { return $root.TrimEnd('\') }
    }
    return $null
}

if ($Drive -ne "") {
    $Mount = $Drive.TrimEnd('\')
    if (-not (Test-Path (Join-Path $Mount ".kobo\version"))) { Write-Host "Fout: $Mount lijkt geen Kobo te zijn."; exit 1 }
} else {
    $Mount = Find-Kobo
    if (-not $Mount) {
        if ($Wait) {
            Write-Host "Wachten op de Kobo... (sluit hem aan en tik op 'Verbinden'; Ctrl+C om te stoppen)"
            while (-not $Mount) { Start-Sleep -Seconds 2; $Mount = Find-Kobo }
            Start-Sleep -Seconds 3
        } else {
            Write-Host "Geen Kobo gevonden. Sluit hem aan, tik op 'Verbinden' en probeer opnieuw (of gebruik -Wait)."
            exit 1
        }
    }
}

$KOReader = Join-Path $Mount ".adds\koreader"
$VersionLine = (Get-Content (Join-Path $Mount ".kobo\version") -TotalCount 1).Trim()
Write-Host "Kobo gevonden op: $Mount"
Write-Host "Firmware/model-regel: $VersionLine"
if (-not (Test-Path $KOReader)) { Write-Host "Fout: KOReader niet gevonden in $KOReader. Installeer eerst KOReader."; exit 1 }

$DevId = $VersionLine.Substring($VersionLine.Length - 3)
$Supported = 2
switch ($DevId) {
    "388" { $Model = "Kobo Libra 2"; $Supported = 1 }
    "389" { $Model = "Kobo Elipsa 2E"; $Supported = 1 }
    { $_ -in "390", "391", "393" } { $Model = "Kobo Libra Colour / Clara BW / Clara Colour (waarschijnlijk)"; $Supported = 1 }
    "383" { $Model = "Kobo Sage (waarschijnlijk)"; $Supported = 0 }
    "386" { $Model = "Kobo Clara 2E (waarschijnlijk)"; $Supported = 0 }
    "387" { $Model = "Kobo Elipsa (waarschijnlijk)"; $Supported = 0 }
    default { $Model = "onbekend" }
}
Write-Host "Model (op basis van ID $DevId): $Model"
if ($Supported -eq 0) {
    Write-Host ""
    Write-Host "LET OP: dit model wordt niet ondersteund door kobo.koplugin's Bluetooth."
    Write-Host "Zie README.md, sectie 'Mijn model wordt niet ondersteund'. De oude plugin blijft ingeschakeld."
    Write-Host ""
}

# Back-up naar de computer
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$Backup = Join-Path $Here "backups\$Stamp"
New-Item -ItemType Directory -Force -Path $Backup | Out-Null
Write-Host "Back-up maken in: $Backup"
$Settings = Join-Path $KOReader "settings.reader.lua"
if (Test-Path $Settings) { Copy-Item $Settings $Backup }
$Plugins = Join-Path $KOReader "plugins"
$Others = @()
if (Test-Path $Plugins) {
    Get-ChildItem $Plugins -Directory -Filter "*.koplugin" | ForEach-Object {
        $n = $_.Name -replace '\.koplugin$', ''
        $l = $n.ToLower()
        $isBt = ($l -like "*bluetooth*") -or ($l -like "bt*") -or ($l -like "*pageturn*") -or ($l -like "*page_turn*") -or ($l -like "*btremote*")
        if ($n -eq "kobo" -or $isBt) { Copy-Item $_.FullName (Join-Path $Backup $_.Name) -Recurse }
        if ($n -ne "kobo" -and $isBt) { $Others += $n }
    }
}
$Patches = Join-Path $KOReader "patches"
if (Test-Path $Patches) { Copy-Item $Patches (Join-Path $Backup "patches") -Recurse }
if ($Others.Count -gt 0) {
    Write-Host "Andere Bluetooth-plugin(s) gevonden: $($Others -join ', ')"
    if ($Supported -ne 0) { Write-Host "  -> worden bij de eerste start automatisch uitgeschakeld (niet verwijderd)." }
}

# Installeren
Write-Host ""
Write-Host "Installeren..."
New-Item -ItemType Directory -Force -Path $Plugins, $Patches | Out-Null
$Target = Join-Path $Plugins "kobo.koplugin"
if (Test-Path $Target) { Remove-Item $Target -Recurse -Force }
Copy-Item (Join-Path $Payload "plugins\kobo.koplugin") $Target -Recurse
Copy-Item (Join-Path $Payload "patches\2-bt-remote-setup.lua") $Patches -Force

Write-Host ""
Write-Host "Klaar. Geinstalleerd:"
Write-Host "  $Target"
Write-Host "  $(Join-Path $Patches '2-bt-remote-setup.lua')"
Write-Host ""
Write-Host "Volgende stappen:"
Write-Host "  1. Werp de Kobo veilig uit en koppel los."
Write-Host "  2. Start KOReader (opnieuw). Bluetooth gaat nu vanzelf aan."
Write-Host "  3. Koppel de 8BitDo een keer: zie README.md, stap 'Eerste keer koppelen'."
