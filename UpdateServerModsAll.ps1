# Bolsonaro Gameplays - HOST script, "ALL MODS" version
#
# Same as UpdateServerMods, but turns EVERY subscribed mod on in the server,
# including client-side ones (Project Viewpoint, ZombieBuddy, ...) and mods that
# UpdateServerMods excludes on purpose. Only mods that can't work together are skipped:
# mods marked incompatible with another mod, and mods their author marked obsolete.
# Everyone who joins must then have ALL of these mods (friends: CopySteamMods.bat).
#
# Usage:  UpdateServerModsAll.ps1 [-WindowsUser <name>] [-ServerName <name>]
# Run it with the server STOPPED.

param(
  [string]$WindowsUser = $env:USERNAME,
  [string]$ServerName = 'bolsonaro_gameplays'
)

# ---- Optional tweaks -------------------------------------------------------
# When two mods say they are incompatible, the one listed here wins.
$PreferredMods = @('Authentic Z - Current')
# Mod IDs that should never be turned on in the server, even if subscribed.
$ExcludedMods = @()
# Client-side only: copied to Zomboid\mods for YOUR game, but never turned on in the server
# Java mods (ZombieBuddy, Project Viewpoint, ...) are detected
# automatically; add other mod IDs or Workshop item IDs here if needed.
$ClientOnlyMods = @()
$ClientOnlyWorkshopItems = @()
# (ALL MODS version: nothing is kept client-side only)
# ---------------------------------------------------------------------------

function Get-ModInfoValues($path, $key) {
  $vals = @()
  foreach ($ln in (Get-Content -LiteralPath $path -ErrorAction SilentlyContinue)) {
    if ($ln -match ('^\s*' + $key + '\s*=\s*(.*)$')) {
      foreach ($p in ($Matches[1] -split '[,;]')) {
        $v = $p.Trim().TrimStart('\').Trim()
        if ($v) { $vals += $v }
      }
    }
  }
  return ,$vals
}

function Get-VersionMin($name) {
  $min = ($name -split '-')[0]
  try { return [version]($(if ($min -match '\.') { $min } else { "$min.0" })) } catch { return $null }
}

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
$dest = Join-Path $zomboid 'mods'
$ini = Join-Path (Join-Path $zomboid 'Server') ($ServerName + '.ini')
if (-not (Test-Path -LiteralPath $ini)) { Write-Host "Server config not found: $ini" -ForegroundColor Red; exit 1 }
New-Item -ItemType Directory -Force -Path $dest | Out-Null
$manifest = Join-Path $dest 'copied_steam_mods.txt'          # shared with CopySteamMods
$legacyManifest = Join-Path $dest 'bolsonaro_copied_mods.txt'

$gameVersion = [version]'42.99'
$vt = Join-Path $zomboid 'version.txt'
if (Test-Path -LiteralPath $vt) {
  $first = (Get-Content -LiteralPath $vt -TotalCount 1)
  if ($first -match '^(\d+\.\d+)') { $gameVersion = [version]$Matches[1] }
}

$running = @(Get-CimInstance Win32_Process -Filter "Name='java.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match 'zombie\.network\.GameServer' })
if ($running.Count -gt 0) {
  Write-Host 'WARNING: a Project Zomboid server is running. Stop it (type quit) and run this again.' -ForegroundColor Red
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

# ---- Scan subscribed mods --------------------------------------------------
$mods = @{}          # modID -> info
$folderSeen = @{}
foreach ($ws in $wsDirs) {
  foreach ($item in (Get-ChildItem -LiteralPath $ws -Directory)) {
    $modsDir = Join-Path $item.FullName 'mods'
    if (-not (Test-Path -LiteralPath $modsDir)) { continue }
    foreach ($folder in (Get-ChildItem -LiteralPath $modsDir -Directory)) {
      if ($folderSeen.ContainsKey($folder.Name)) { continue }
      # Pick the mod.info that Build 42 uses: the best matching version folder, else the root one
      $best = $null; $bestVer = $null
      foreach ($sub in (Get-ChildItem -LiteralPath $folder.FullName -Directory | Where-Object { $_.Name -match '^\d' })) {
        $v = Get-VersionMin $sub.Name
        if ($v -and $v -le $gameVersion -and (Test-Path -LiteralPath (Join-Path $sub.FullName 'mod.info'))) {
          if (-not $bestVer -or $v -gt $bestVer) { $best = $sub.FullName; $bestVer = $v }
        }
      }
      $infoDir = $(if ($best) { $best } else { $folder.FullName })
      if (-not (Test-Path -LiteralPath (Join-Path $infoDir 'mod.info'))) { $infoDir = Join-Path $folder.FullName 'common' }
      $infoFile = Join-Path $infoDir 'mod.info'
      if (-not (Test-Path -LiteralPath $infoFile)) { continue }
      $ids = Get-ModInfoValues $infoFile 'id'
      if ($ids.Count -eq 0) { continue }
      $maps = @()
      foreach ($d in @($folder.FullName, $infoDir, (Join-Path $folder.FullName 'common'))) {
        $md = Join-Path $d 'media\maps'
        if (Test-Path -LiteralPath $md) {
          foreach ($mp in (Get-ChildItem -LiteralPath $md -Directory)) {
            if ((Test-Path -LiteralPath (Join-Path $mp.FullName 'map.info')) -and ($maps -notcontains $mp.Name)) { $maps += $mp.Name }
          }
        }
      }
      $isJava = (Test-Path -LiteralPath (Join-Path $folder.FullName 'libs\ZombieBuddy.jar'))
      foreach ($d in @($folder.FullName, $infoDir, (Join-Path $folder.FullName 'common'))) {
        if (Test-Path -LiteralPath (Join-Path $d 'media\java')) { $isJava = $true }
      }
      $folderSeen[$folder.Name] = $true
      $nameLine = (Get-Content -LiteralPath $infoFile | Where-Object { $_ -match '^\s*name\s*=' } | Select-Object -First 1)
      $modName = $(if ($nameLine) { ($nameLine -split '=', 2)[1].Trim() } else { $folder.Name })
      $mods[$ids[0]] = [pscustomobject]@{
        Id = $ids[0]; Name = $modName; Folder = $folder.Name; Source = $folder.FullName; WorkshopId = $item.Name
        Requires = (Get-ModInfoValues $infoFile 'require')
        Incompatible = (Get-ModInfoValues $infoFile 'incompatible')
        Maps = $maps
        ClientOnly = $false   # ALL MODS version
      }
    }
  }
}
Write-Host ("Subscribed mods found: {0}" -f $mods.Count) -ForegroundColor Cyan

# ---- Copy them into Zomboid\mods -----------------------------------------
$names = @($mods.Values | ForEach-Object { $_.Folder } | Sort-Object)
$previous = @()
foreach ($mf in @($manifest, $legacyManifest)) { if (Test-Path -LiteralPath $mf) { $previous += @(Get-Content -LiteralPath $mf) } }
if ($previous.Count -gt 0) {
  foreach ($old in ($previous | Select-Object -Unique)) {
    if ($old -and ($names -notcontains $old)) {
      $p = Join-Path $dest $old
      if (Test-Path -LiteralPath $p) { Write-Host "Removing unsubscribed mod: $old" -ForegroundColor DarkYellow; Remove-Item -LiteralPath $p -Recurse -Force }
    }
  }
}
$failed = @(); $i = 0
foreach ($m in ($mods.Values | Sort-Object Folder)) {
  $i++
  Write-Host ("[{0}/{1}] {2}" -f $i, $mods.Count, $m.Folder)
  robocopy $m.Source (Join-Path $dest $m.Folder) /MIR /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -ge 8) { $failed += $m.Folder }
}
Set-Content -LiteralPath $manifest -Value $names
if (Test-Path -LiteralPath $legacyManifest) { Remove-Item -LiteralPath $legacyManifest -Force }

# ---- Decide which mods the server uses -----------------------------------
$text = [System.IO.File]::ReadAllText($ini)
$curMods = @()
if ($text -match '(?m)^Mods=([^\r\n]*)') { $curMods = @($Matches[1] -split ';' | ForEach-Object { $_.Trim().TrimStart('\') } | Where-Object { $_ }) }
$curMap = @()
if ($text -match '(?m)^Map=([^\r\n]*)') { $curMap = @($Matches[1] -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }

# priority: preferred, then the current server order, then new mods alphabetically
# a mod that needs a client-side-only mod is client-side only too
do {
  $changed = $false
  foreach ($m in $mods.Values) {
    if ($m.ClientOnly) { continue }
    foreach ($r in $m.Requires) { if ($mods.ContainsKey($r) -and $mods[$r].ClientOnly) { $m.ClientOnly = $true; $changed = $true; break } }
  }
} while ($changed)
$clientOnly = @($mods.Values | Where-Object { $_.ClientOnly } | ForEach-Object { $_.Id } | Sort-Object)
$order = @()
foreach ($id in ($PreferredMods + $curMods + @($mods.Keys | Sort-Object))) {
  if ($mods.ContainsKey($id) -and ($order -notcontains $id) -and ($ExcludedMods -notcontains $id) -and ($clientOnly -notcontains $id)) { $order += $id }
}
$accepted = New-Object System.Collections.ArrayList
$skipped = @{}
foreach ($id in $order) {
  if ($mods[$id].Name -match '(?i)obsolete|do not use|deprecated') { $skipped[$id] = 'marked obsolete by its author: ' + $mods[$id].Name; continue }
  $clash = $null
  foreach ($a in $accepted) {
    if ($mods[$id].Incompatible -contains $a -or $mods[$a].Incompatible -contains $id) { $clash = $a; break }
  }
  if ($clash) { $skipped[$id] = "incompatible with $clash" } else { [void]$accepted.Add($id) }
}
# drop mods whose requirements are not available (repeat until stable)
do {
  $changed = $false
  foreach ($id in @($accepted)) {
    $miss = @($mods[$id].Requires | Where-Object { $accepted -notcontains $_ })
    if ($miss.Count -gt 0) { $accepted.Remove($id); $skipped[$id] = 'needs ' + ($miss -join ', '); $changed = $true }
  }
} while ($changed)

# load order: every mod after the mods it requires (keeps the order above otherwise)
$final = New-Object System.Collections.ArrayList
function Add-InOrder($id, $stack) {
  if ($final -contains $id) { return }
  if ($stack -contains $id) { return }   # circular requirement: ignore
  foreach ($r in $mods[$id].Requires) { if ($accepted -contains $r) { Add-InOrder $r ($stack + $id) } }
  if ($final -notcontains $id) { [void]$final.Add($id) }
}
foreach ($id in $accepted) { Add-InOrder $id @() }

# maps: maps from enabled mods go first, vanilla/other entries keep their order
$allModMaps = @($mods.Values | ForEach-Object { $_.Maps } | Where-Object { $_ })
$enabledMaps = @()
foreach ($id in $final) { foreach ($mp in $mods[$id].Maps) { if ($enabledMaps -notcontains $mp) { $enabledMaps += $mp } } }
$newMap = @($enabledMaps) + @($curMap | Where-Object { ($allModMaps -notcontains $_) -and ($enabledMaps -notcontains $_) })
if ($newMap.Count -eq 0) { $newMap = @('Muldraugh, KY') }

# ---- Write the server config ----------------------------------------------
$backup = $ini + '.bak-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
Copy-Item -LiteralPath $ini -Destination $backup
$modsLine = 'Mods=' + ($final -join ';')
$mapLine = 'Map=' + ($newMap -join ';')
$text = [regex]::Replace($text, '(?m)^Mods=[^\r\n]*', $modsLine.Replace('$', '$$'))
$text = [regex]::Replace($text, '(?m)^Map=[^\r\n]*', $mapLine.Replace('$', '$$'))
[System.IO.File]::WriteAllText($ini, $text, (New-Object System.Text.UTF8Encoding($false)))

# ---- Summary ----------------------------------------------------------------
$added = @($final | Where-Object { $curMods -notcontains $_ })
$removed = @($curMods | Where-Object { $final -notcontains $_ })
Write-Host ''
Write-Host ("Copied {0} mod folders to {1}" -f ($mods.Count - $failed.Count), $dest) -ForegroundColor Green
Write-Host ("Server '{0}' now uses {1} mods  (+{2} added, -{3} removed)" -f $ServerName, $final.Count, $added.Count, $removed.Count) -ForegroundColor Green
if ($added.Count)   { Write-Host ('  Added:   ' + ($added -join ', ')) }
if ($removed.Count) { Write-Host ('  Removed: ' + ($removed -join ', ')) }
if ($skipped.Count) {
  Write-Host '  Not turned on:' -ForegroundColor Yellow
  foreach ($k in ($skipped.Keys | Sort-Object)) { Write-Host ("    {0}  ({1})" -f $k, $skipped[$k]) -ForegroundColor Yellow }
}
if ($ExcludedMods.Count) { Write-Host ('  Excluded by you: ' + ($ExcludedMods -join ', ')) }
if ($clientOnly.Count) { Write-Host ('  Client-side only (copied for your game, NOT on the server): ' + ($clientOnly -join ', ')) -ForegroundColor Cyan }
Write-Host ('  Map= ' + ($newMap -join ';'))
if ($failed.Count) { Write-Host ('Copy errors: ' + ($failed -join ', ')) -ForegroundColor Red }
Write-Host ("Config backup: {0}" -f $backup)
