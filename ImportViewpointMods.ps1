# Bolsonaro Gameplays - import your Project Viewpoint mods (CLIENT SIDE ONLY)
#
# Copies every mod from your Viewpoint Workshop collection (plus ZombieBuddy) from the
# Steam Workshop folder into C:\Users\<WindowsUser>\Zomboid\mods, so your game can use
# them with -nosteam. It never touches the server config, so the server can keep running.
# It also saves the collection's item list to client_only_workshop_items.txt, which
# UpdateServerMods uses to keep these mods OFF the server.
#
# Usage:  ImportViewpointMods.ps1 [-WindowsUser <name>] [-CollectionId <id>]
# Close Project Zomboid (the game) before running it. Run it again after mods update.

param(
  [string]$WindowsUser = $env:USERNAME,
  [string]$CollectionId = '3817311887'
)

$clientListFile = Join-Path $PSScriptRoot 'client_only_workshop_items.txt'

# ---- Paths ----------------------------------------------------------------
$WindowsUser = $WindowsUser.Trim().Trim('"')
if (-not $WindowsUser) { $WindowsUser = $env:USERNAME }
$usersRoot = Split-Path $env:USERPROFILE -Parent
$profileDir = Join-Path $usersRoot $WindowsUser
if (-not (Test-Path -LiteralPath $profileDir)) {
  Write-Host "Windows user folder not found: $profileDir" -ForegroundColor Red
  $known = @(Get-ChildItem -LiteralPath $usersRoot -Directory -ErrorAction SilentlyContinue | Where-Object { @('Public','Default','Default User','All Users') -notcontains $_.Name } | ForEach-Object { $_.Name })
  Write-Host ('Users on this PC: ' + ($known -join ', '))
  exit 1
}
$dest = Join-Path (Join-Path $profileDir 'Zomboid') 'mods'
New-Item -ItemType Directory -Force -Path $dest | Out-Null
$manifest = Join-Path $dest 'viewpoint_copied_mods.txt'

if (Get-Process -Name 'ProjectZomboid64', 'ProjectZomboid32' -ErrorAction SilentlyContinue) {
  Write-Host 'Project Zomboid (the game) is open. Close it and run this again - its mod files are in use.' -ForegroundColor Red
  exit 1
}

# ---- Find Steam Workshop folders ------------------------------------------
$libs = @('C:\Program Files (x86)\Steam')
$steam = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction SilentlyContinue).SteamPath
if ($steam) {
  $steam = $steam -replace '/', '\'
  $libs += $steam
  $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
  if (Test-Path -LiteralPath $vdf) {
    foreach ($m in (Select-String -LiteralPath $vdf -Pattern '"path"\s+"([^"]+)"')) {
      $libs += ($m.Matches[0].Groups[1].Value -replace '\\\\', '\')
    }
  }
}
$wsDirs = @($libs | ForEach-Object { $_.ToLower().TrimEnd('\') } | Select-Object -Unique | ForEach-Object { Join-Path $_ 'steamapps\workshop\content\108600' } | Where-Object { Test-Path -LiteralPath $_ })
if ($wsDirs.Count -eq 0) { Write-Host 'Could not find the Project Zomboid Workshop folder.' -ForegroundColor Red; exit 1 }

function Find-Item($wid) {
  foreach ($ws in $wsDirs) { $p = Join-Path $ws $wid; if (Test-Path -LiteralPath (Join-Path $p 'mods')) { return $p } }
  return $null
}
function Test-JavaMod($folderPath) {
  if (Test-Path -LiteralPath (Join-Path $folderPath 'libs\ZombieBuddy.jar')) { return $true }
  foreach ($d in @($folderPath) + @(Get-ChildItem -LiteralPath $folderPath -Directory | Where-Object { $_.Name -match '^\d' -or $_.Name -eq 'common' } | ForEach-Object { $_.FullName })) {
    if (Test-Path -LiteralPath (Join-Path $d 'media\java')) { return $true }
  }
  return $false
}

# ---- Which Workshop items are in the collection? ----------------------------
$items = @()
$source = ''
try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  $pending = @($CollectionId); $visited = @{}
  while ($pending.Count -gt 0) {
    $batch = @($pending | Where-Object { -not $visited.ContainsKey($_) }); $pending = @()
    if ($batch.Count -eq 0) { break }
    foreach ($b in $batch) { $visited[$b] = $true }
    $body = @{ collectioncount = $batch.Count }
    for ($k = 0; $k -lt $batch.Count; $k++) { $body["publishedfileids[$k]"] = $batch[$k] }
    $r = Invoke-RestMethod -Method Post -Uri 'https://api.steampowered.com/ISteamRemoteStorage/GetCollectionDetails/v1/' -Body $body -TimeoutSec 30
    foreach ($c in $r.response.collectiondetails) {
      foreach ($ch in $c.children) {
        $id = [string]$ch.publishedfileid
        if ([int]$ch.filetype -eq 2) { $pending += $id } elseif ($items -notcontains $id) { $items += $id }
      }
    }
  }
  if ($items.Count -gt 0) { $source = "Steam collection $CollectionId" }
} catch {
  Write-Host ("Could not read the collection from Steam ({0})." -f $_.Exception.Message) -ForegroundColor Yellow
}
if ($items.Count -eq 0 -and (Test-Path -LiteralPath $clientListFile)) {
  $items = @(Get-Content -LiteralPath $clientListFile | Where-Object { $_ -match '^\d+$' })
  if ($items.Count) { $source = 'last saved list (client_only_workshop_items.txt)' }
}
if ($items.Count -eq 0) {
  # Last resort: every subscribed item with a Java (ZombieBuddy) mod or "Viewpoint" in a mod name
  foreach ($ws in $wsDirs) {
    foreach ($it in (Get-ChildItem -LiteralPath $ws -Directory)) {
      $md = Join-Path $it.FullName 'mods'
      if (-not (Test-Path -LiteralPath $md)) { continue }
      foreach ($f in (Get-ChildItem -LiteralPath $md -Directory)) {
        if ($f.Name -match '(?i)viewpoint' -or (Test-JavaMod $f.FullName)) { if ($items -notcontains $it.Name) { $items += $it.Name }; break }
      }
    }
  }
  $source = 'your subscribed Viewpoint / Java mods (Steam unreachable)'
}

# Always include ZombieBuddy (Viewpoint needs it) if you are subscribed to it
foreach ($ws in $wsDirs) {
  foreach ($it in (Get-ChildItem -LiteralPath $ws -Directory)) {
    if ($items -contains $it.Name) { continue }
    $md = Join-Path $it.FullName 'mods'
    if (Test-Path -LiteralPath $md) {
      foreach ($f in (Get-ChildItem -LiteralPath $md -Directory)) {
        if (Test-Path -LiteralPath (Join-Path $f.FullName 'libs\ZombieBuddy.jar')) { $items += $it.Name; break }
      }
    }
  }
}
Write-Host ("Viewpoint items: {0}  (from {1})" -f $items.Count, $source) -ForegroundColor Cyan
Set-Content -LiteralPath $clientListFile -Value (@('# Client-side only Workshop items (Viewpoint collection ' + $CollectionId + '). UpdateServerMods keeps these off the server.') + $items)

# ---- Copy -------------------------------------------------------------------
$sources = @{}; $missing = @()
foreach ($wid in $items) {
  $p = Find-Item $wid
  if (-not $p) { $missing += $wid; continue }
  foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $p 'mods') -Directory)) {
    if (-not $sources.ContainsKey($f.Name)) { $sources[$f.Name] = $f.FullName }
  }
}
$names = @($sources.Keys | Sort-Object)
if (Test-Path -LiteralPath $manifest) {
  foreach ($old in (Get-Content -LiteralPath $manifest)) {
    if ($old -and ($names -notcontains $old)) {
      $p = Join-Path $dest $old
      if (Test-Path -LiteralPath $p) { Write-Host "Removing mod no longer in the collection: $old" -ForegroundColor DarkYellow; Remove-Item -LiteralPath $p -Recurse -Force }
    }
  }
}
$failed = @(); $i = 0
foreach ($name in $names) {
  $i++
  Write-Host ("[{0}/{1}] {2}" -f $i, $names.Count, $name)
  robocopy $sources[$name] (Join-Path $dest $name) /MIR /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -ge 8) { $failed += $name }
}
Set-Content -LiteralPath $manifest -Value $names

Write-Host ''
Write-Host ("Viewpoint mods copied to {0}: {1}" -f $dest, ($names.Count - $failed.Count)) -ForegroundColor Green
if ($failed.Count) { Write-Host ('Copy errors (is the game still open?): ' + ($failed -join ', ')) -ForegroundColor Red }
if ($missing.Count) {
  Write-Host 'Not downloaded yet - subscribe to these, let Steam download them, then run this again:' -ForegroundColor Yellow
  foreach ($w in $missing) { Write-Host ("  https://steamcommunity.com/sharedfiles/filedetails/?id={0}" -f $w) }
}
Write-Host 'Next: open the game, go to Mods, enable ZombieBuddy and the Viewpoint mods, then restart the game.' -ForegroundColor Cyan
