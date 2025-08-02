[CmdletBinding(PositionalBinding=$false, DefaultParameterSetName='Move')]
param(
    [Parameter(ParameterSetName='Move', Position=0, ValueFromRemainingArguments=$true)]
    [string[]]$TargetPath,

    [Parameter(ParameterSetName='Restore')]
    [switch]$Restore,

    [Parameter(ParameterSetName='Link')]
    [Alias('MakeLink')]
    [switch]$Link,

    [Parameter(ParameterSetName='Clean')]
    [switch]$Clean,

    [switch]$DryRun,

    [string]$WorkingDirectory = (Get-Location).Path,

    [string]$TargetSubDirectory
)

$Global:OriginMapPath = Join-Path -Path $WorkingDirectory -ChildPath ".origin"

function Ensure-Elevation {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "Elevation required. Prompting for admin..."
        $quotedScript = '"' + $PSCommandPath + '"'
        $argList = @()

        if ($PSCmdlet.ParameterSetName -eq 'Move' -and $TargetPath) {
            foreach ($p in $TargetPath) {
                $clean = [Regex]::Replace($p, '\\+$', '')
                $argList += "-TargetPath `"$clean`""
            }
        }

        switch ($PSCmdlet.ParameterSetName) {
            'Restore' { $argList += "-Restore" }
            'Link'    { $argList += "-Link" }
            'Clean'   { $argList += "-Clean" }
        }

        if ($DryRun)              { $argList += "-DryRun" }
        if ($TargetSubDirectory)  { $argList += "-TargetSubDirectory `"$TargetSubDirectory`"" }
        if ($WorkingDirectory)    { $argList += "-WorkingDirectory `"$WorkingDirectory`"" }

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File $quotedScript $($argList -join ' ')"
        $psi.Verb = "runas"
        try {
            [System.Diagnostics.Process]::Start($psi) | Out-Null
        } catch {
            Write-Error "User cancelled the elevation prompt or an error occurred."
        }
        exit
    }
}

Ensure-Elevation

function Ensure-OriginFile {
    if (!(Test-Path $Global:OriginMapPath)) {
        New-Item -Path $Global:OriginMapPath -ItemType File -Force | Out-Null
    }
}

function Add-To-OriginMap {
    param(
        [string]$CurrentPath,
        [string]$OriginalPath
    )
    Ensure-OriginFile
    $map = Load-OriginMap
    if (-not $map.ContainsKey($CurrentPath)) {
        "$CurrentPath|$OriginalPath" | Out-File -FilePath $Global:OriginMapPath -Encoding UTF8 -Append
    }
}

function Load-OriginMap {
    $map = @{}
    if (Test-Path $Global:OriginMapPath) {
        Get-Content $Global:OriginMapPath | ForEach-Object {
            if ($_ -match "^(.*?)\|(.*)$") {
                $map[$matches[1]] = $matches[2]
            }
        }
    }
    return $map
}

function Save-OriginMap {
    param([hashtable]$Map)
    Ensure-OriginFile
    if ($Map.Count -eq 0) {
        # Explicitly clear the file when no entries remain
        Set-Content -Path $Global:OriginMapPath -Value '' -NoNewline
        return
    }
    $Map.GetEnumerator() | ForEach-Object {
        "$($_.Key)|$($_.Value)"
    } | Set-Content -Path $Global:OriginMapPath -Encoding UTF8
}

function New-SafeSymlink {
    param(
        [Parameter(Mandatory=$true)][string]$LinkPath,
        [Parameter(Mandatory=$true)][string]$TargetPath,
        [Parameter(Mandatory=$true)][bool]$IsDirectory
    )
    try {
        if ($IsDirectory) {
            New-Item -ItemType SymbolicLink -Path $LinkPath -Target $TargetPath -Force -ErrorAction Stop | Out-Null
        } else {
            New-Item -ItemType SymbolicLink -Path $LinkPath -Target $TargetPath -Force -ErrorAction Stop | Out-Null
        }
        return
    } catch {
        # Fallback to cmd mklink for environments where New-Item symlink fails
        $link = '"' + $LinkPath + '"'
        $target = '"' + $TargetPath + '"'
        $mklinkArgs = if ($IsDirectory) { "/c mklink /D $link $target" } else { "/c mklink $link $target" }
        $proc = Start-Process -FilePath "cmd.exe" -ArgumentList $mklinkArgs -NoNewWindow -PassThru -Wait -ErrorAction SilentlyContinue
        if (-not $proc -or $proc.ExitCode -ne 0) {
            throw "Failed to create symlink: $LinkPath -> $TargetPath (exit code $($proc.ExitCode))"
        }
    }
}

function Move-And-Link {
    param([string]$Path)

    $Path = [Regex]::Replace($Path, '\\+$', '')

    try {
        $OriginalPath = Resolve-Path -Path $Path -ErrorAction Stop
        $Item = Get-Item -LiteralPath $OriginalPath -ErrorAction Stop
        $FileName = $Item.Name

        $TargetDir = $WorkingDirectory
        if ($TargetSubDirectory) {
            $TargetDir = Join-Path -Path $WorkingDirectory -ChildPath $TargetSubDirectory
            if (!(Test-Path $TargetDir)) {
                New-Item -Path $TargetDir -ItemType Directory | Out-Null
            }
        }

        $NewPath = Join-Path -Path $TargetDir -ChildPath $FileName

        if (Test-Path $NewPath) {
            throw "Target '$FileName' already exists in destination directory."
        }

        if ($DryRun) {
            Write-Host "Would move '$OriginalPath' to '$NewPath'"
            Write-Host "Would create symlink at '$OriginalPath'"
            Write-Host "Would record in .origin file"
            return
        }

        Move-Item -Path $OriginalPath -Destination $NewPath

        $isDir = $Item.PSIsContainer
        New-SafeSymlink -LinkPath $OriginalPath -TargetPath $NewPath -IsDirectory:$isDir

        Add-To-OriginMap -CurrentPath $NewPath -OriginalPath $OriginalPath
        Write-Host "Moved and linked '$FileName'. Origin recorded in .origin"

    } catch {
        $msg = "Error processing '$Path': $($_.Exception.Message)"
        Write-Host "`n$msg" -ForegroundColor Red
        "$msg`n" | Out-File -FilePath "$env:TEMP\move-symlink-error.log" -Encoding UTF8 -Append
    }
}

function Restore-From-Origin {
    $map = Load-OriginMap
    $newMap = @{}

    foreach ($pair in $map.GetEnumerator()) {
        $linkedItem = $pair.Key
        $originalPath = $pair.Value

        try {
            if ($DryRun) {
                Write-Host "Would remove symlink '$originalPath'"
                Write-Host "Would move '$linkedItem' back to '$originalPath'"
                continue
            }

            if (Test-Path $originalPath) { Remove-Item $originalPath -Force -Recurse }
            Move-Item -Path $linkedItem -Destination $originalPath
            Write-Host "Restored '$originalPath'"
        } catch {
            $msg = "Restore error for '$originalPath': $($_.Exception.Message)"
            Write-Host "`n$msg" -ForegroundColor Red
            "$msg`n" | Out-File -FilePath "$env:TEMP\move-symlink-error.log" -Encoding UTF8 -Append
            $newMap[$linkedItem] = $originalPath
        }
    }

    Save-OriginMap -Map $newMap
}

function Make-Link-From-Origin {
    $map = Load-OriginMap

    foreach ($pair in $map.GetEnumerator()) {
        $itemPath = $pair.Key
        $originalPath = $pair.Value

        try {
            if ($DryRun) {
                Write-Host "Would create symlink at '$originalPath' -> '$itemPath'"
                continue
            }

            if (Test-Path $originalPath) { Remove-Item $originalPath -Force -Recurse }
            $isDir = (Get-Item -Path $itemPath).PSIsContainer
            New-SafeSymlink -LinkPath $originalPath -TargetPath $itemPath -IsDirectory:$isDir

            Write-Host "Linked '$originalPath' -> '$itemPath'"
        } catch {
            $msg = "Link error for '$originalPath': $($_.Exception.Message)"
            Write-Host "`n$msg" -ForegroundColor Red
            "$msg`n" | Out-File -FilePath "$env:TEMP\move-symlink-error.log" -Encoding UTF8 -Append
        }
    }
}

function Clean-OriginLinks {
    $map = Load-OriginMap

    foreach ($pair in $map.GetEnumerator()) {
        try {
            if (Test-Path $pair.Key) {
                Remove-Item $pair.Key -Force -Recurse
                Write-Host "Removed '$($pair.Key)'"
            }
        } catch {
            $msg = "Cleanup error for '$($pair.Key)': $($_.Exception.Message)"
            Write-Host "`n$msg" -ForegroundColor Red
            "$msg`n" | Out-File -FilePath "$env:TEMP\move-symlink-error.log" -Encoding UTF8 -Append
        }
    }

    if (Test-Path $Global:OriginMapPath) {
        Remove-Item $Global:OriginMapPath -Force
        Write-Host "Removed .origin file"
    }
}

# Main logic
switch ($PSCmdlet.ParameterSetName) {
    'Restore' { Restore-From-Origin }
    'Link'    { Make-Link-From-Origin }
    'Clean'   { Clean-OriginLinks }
    default {
        if ($TargetPath) {
            foreach ($p in $TargetPath) {
                Move-And-Link -Path $p
            }
        } else {
            Write-Host "Please provide -TargetPath, -Restore, -Link, or -Clean."
        }
    }
}

Write-Host "Args:"
Write-Host "ParameterSet: $($PSCmdlet.ParameterSetName)"
Write-Host "TargetPath: $TargetPath"
Write-Host "TargetSubDirectory: $TargetSubDirectory"
Write-Host "Restore: $Restore"
Write-Host "Link: $Link"
Write-Host "Clean: $Clean"
Write-Host "DryRun: $DryRun"
Write-Host "WorkingDirectory: $WorkingDirectory"
Write-Host "Press Enter to exit..."
Read-Host | Out-Null
