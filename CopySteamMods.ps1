# CopySteamMods - copies every Project Zomboid mod you are subscribed to on the
# Steam Workshop into C:\Users\<WindowsUser>\Zomboid\mods.
#
# Useful when the game (or a server) runs with -nosteam, which cannot see Workshop mods.
# Run it again after you subscribe/unsubscribe or a mod updates (let Steam finish
# downloading first). Mods it copied earlier that you are no longer subscribed to are
# removed; folders it did not create are never touched.
#
# Usage:  CopySteamMods.ps1 [-WindowsUser <name>]     (default: the user running it)

param(
  [string]$WindowsUser = $env:USERNAME
)

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
$zomboid = Join-Path $profileDir 'Zomboid'
if (-not (Test-Path -LiteralPath $zomboid)) { Write-Host "Note: $zomboid does not exist yet (open Project Zomboid once on this user). Creating it." -ForegroundColor Yellow }
$dest = Join-Path $zomboid 'mods'
New-Item -ItemType Directory -Force -Path $dest | Out-Null
$manifest = Join-Path $dest 'copied_steam_mods.txt'
$legacyManifest = Join-Path $dest 'bolsonaro_copied_mods.txt'
Write-Host "Copying mods to: $dest"

if (Get-Process -Name 'ProjectZomboid64', 'ProjectZomboid32' -ErrorAction SilentlyContinue) {
  Write-Host 'Project Zomboid is open - close it first so its mod files can be updated.' -ForegroundColor Red
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
if ($wsDirs.Count -eq 0) { Write-Host 'Could not find the Project Zomboid Workshop folder. Is Project Zomboid installed with Steam?' -ForegroundColor Red; exit 1 }

# ---- Every subscribed mod folder -----------------------------------------
$sources = @{}   # mod folder name -> source path
foreach ($ws in $wsDirs) {
  foreach ($item in (Get-ChildItem -LiteralPath $ws -Directory)) {
    $modsDir = Join-Path $item.FullName 'mods'
    if (-not (Test-Path -LiteralPath $modsDir)) { continue }
    foreach ($folder in (Get-ChildItem -LiteralPath $modsDir -Directory)) {
      if (-not $sources.ContainsKey($folder.Name)) { $sources[$folder.Name] = $folder.FullName }
    }
  }
}
$names = @($sources.Keys | Sort-Object)
Write-Host ("Subscribed mods found: {0}" -f $names.Count) -ForegroundColor Cyan

# ---- Remove mods copied earlier that you are no longer subscribed to --------
$previous = @()
foreach ($mf in @($manifest, $legacyManifest)) { if (Test-Path -LiteralPath $mf) { $previous += @(Get-Content -LiteralPath $mf) } }
foreach ($old in ($previous | Select-Object -Unique)) {
  if ($old -and ($names -notcontains $old)) {
    $p = Join-Path $dest $old
    if (Test-Path -LiteralPath $p) { Write-Host "Removing unsubscribed mod: $old" -ForegroundColor DarkYellow; Remove-Item -LiteralPath $p -Recurse -Force }
  }
}

# ---- Copy ------------------------------------------------------------------
$failed = @(); $i = 0
foreach ($name in $names) {
  $i++
  Write-Host ("[{0}/{1}] {2}" -f $i, $names.Count, $name)
  robocopy $sources[$name] (Join-Path $dest $name) /MIR /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -ge 8) { $failed += $name }
}
Set-Content -LiteralPath $manifest -Value $names
if (Test-Path -LiteralPath $legacyManifest) { Remove-Item -LiteralPath $legacyManifest -Force }

Write-Host ''
Write-Host ("Mods copied: {0} of {1}" -f ($names.Count - $failed.Count), $names.Count) -ForegroundColor Green
if ($failed.Count) { Write-Host ('Copy errors: ' + ($failed -join ', ')) -ForegroundColor Red }
