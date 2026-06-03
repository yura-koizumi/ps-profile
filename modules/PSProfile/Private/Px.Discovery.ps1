#Requires -Version 7.0

function Get-PxExe {
    $e = (Get-Command px -ErrorAction SilentlyContinue)?.Source
    if ($e) { return $e }
    if (-not (Test-PSProfileWindows)) { return $null }
    if (-not $env:LOCALAPPDATA) { return $null }
    return Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\genotrance.px*" `
        -Filter 'px.exe' -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
}

function Get-PxExeCandidates {
    $cands = [System.Collections.Generic.List[object]]::new()
    $cmd = Get-Command px -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) {
        $null = $cands.Add([pscustomobject]@{ Source = 'PATH'; Path = $cmd.Source; Exists = [IO.File]::Exists($cmd.Source) })
    }
    if ((Test-PSProfileWindows) -and $env:LOCALAPPDATA) {
        $wingetRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
        if (Test-Path $wingetRoot) {
            Get-ChildItem "$wingetRoot\genotrance.px*" -Filter 'px.exe' -Recurse -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $null = $cands.Add([pscustomobject]@{ Source = 'winget'; Path = $_.FullName; Exists = $true })
                }
        }
    }
    $seen = @{}
    foreach ($c in $cands) {
        if ($c.Path -and -not $seen.ContainsKey($c.Path)) {
            $seen[$c.Path] = $true
            $c
        }
    }
}

function Get-PxIniPath {
    param([switch]$PreferExisting)
    $cands = @(Get-PxIniCandidates | Select-Object -ExpandProperty Path)
    if ($PreferExisting) {
        $hit = $cands | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($hit) { return $hit }
    }
    return ($cands | Select-Object -First 1)
}

function Get-PxIniCandidates {
    $cands = [System.Collections.Generic.List[object]]::new()
    $exe = Get-PxExe
    if ($exe) {
        $p = Join-Path (Split-Path $exe -Parent) 'px.ini'
        $null = $cands.Add([pscustomobject]@{ Source = 'px.exe dir'; Path = $p; Exists = (Test-Path $p) })
    }
    if ($env:APPDATA) {
        $p = Join-Path $env:APPDATA 'px\px.ini'
        $null = $cands.Add([pscustomobject]@{ Source = 'APPDATA'; Path = $p; Exists = (Test-Path $p) })
    }
    if ((Test-PSProfileWindows) -and $env:USERPROFILE) {
        $p = Join-Path $env:USERPROFILE '.px\px.ini'
        $null = $cands.Add([pscustomobject]@{ Source = 'USERPROFILE'; Path = $p; Exists = (Test-Path $p) })
    }
    $seen = @{}
    foreach ($c in $cands) {
        if ($c.Path -and -not $seen.ContainsKey($c.Path)) {
            $seen[$c.Path] = $true
            $c
        }
    }
}

function Get-PxIniPort {
    param([string]$IniPath)
    if (-not $IniPath -or -not (Test-Path $IniPath)) { return $null }
    $m = Select-String -Path $IniPath -Pattern '^\s*port\s*=\s*(\d+)' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($m -and $m.Matches.Count -gt 0) { return [int]$m.Matches[0].Groups[1].Value }
    return $null
}
