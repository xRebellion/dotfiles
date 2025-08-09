[CmdletBinding(PositionalBinding=$false, DefaultParameterSetName='Move')]
param(
    # --- Parameter Set: CreateLink ---
    # Creates a symlink at a specified path pointing to a source file/folder.
    [Parameter(ParameterSetName='Move', Position=0)]
    [Parameter(ParameterSetName='CreateLink', Position=0)]
    [string]$Source,

    [Parameter(ParameterSetName='CreateLink')]
    [string]$Link,

    # --- Parameter Set: Restore ---
    # Moves items back to their original locations from the backup.
    [Parameter(ParameterSetName='Restore')]
    [switch]$Restore,

    # --- Parameter Set: Relink ---
    # Re-creates all symlinks based on the .origin file.
    [Parameter(ParameterSetName='Relink')]
    [Alias('MakeLink')]
    [switch]$Relink,

    # --- Parameter Set: Clean ---
    # Removes all moved items and the .origin file.
    [Parameter(ParameterSetName='Clean')]
    [switch]$Clean,

    # --- Global Parameters (apply to all sets) ---
    [switch]$DryRun,
    [string]$WorkingDirectory = (Get-Location).Path,
    [string]$TargetSubDirectory
)

# --- Global Variables ---
$Global:OriginMapPath = Join-Path -Path $WorkingDirectory -ChildPath ".origin"
$Global:BackupRootPath = Join-Path -Path $WorkingDirectory -ChildPath ".backups"

#------------------------------------------------------------------------------------

# Checks if the script is running with administrator privileges.
# If not, it relaunches itself in a new, elevated window, passing along all the original arguments.
function Ensure-Elevation {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "Elevation required. Prompting for admin..."
        $quotedScript = '"' + $PSCommandPath + '"'
        $argList = @()

        if ($PSCmdlet.ParameterSetName -eq 'Move' -and $Source) {
            foreach ($p in $Source) {
                $clean = [Regex]::Replace($p, '\\+$', '')
                $argList += "-Source `"$clean`""
            }
        }

        switch ($PSCmdlet.ParameterSetName) {
            'Restore'    { $argList += "-Restore" }
            'Relink'     { $argList += "-Relink" }
            'Clean'      { $argList += "-Clean" }
            'CreateLink' {
                $argList += "-Source `"$Source`""
                $argList += "-Link `"$Link`""
            }
        }

        if ($DryRun)             { $argList += "-DryRun" }
        if ($TargetSubDirectory) { $argList += "-TargetSubDirectory `"$TargetSubDirectory`"" }
        if ($WorkingDirectory)   { $argList += "-WorkingDirectory `"$WorkingDirectory`"" }

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
Set-Location -Path $WorkingDirectory

#------------------------------------------------------------------------------------

# Checks for the `.origin` file in the current directory and creates it if it doesn't exist.
# This file stores the mapping between moved files and their original locations.
function Ensure-OriginFile {
    if (!(Test-Path $Global:OriginMapPath)) {
        New-Item -Path $Global:OriginMapPath -ItemType File -Force | Out-Null
    }
}

#------------------------------------------------------------------------------------

# Checks for the `.backups` directory in the current directory and creates it if it doesn't exist.
# This directory stores timestamped backups of items before they are moved or modified.
function Ensure-BackupRoot {
    if (!(Test-Path $Global:BackupRootPath)) {
        New-Item -Path $Global:BackupRootPath -ItemType Directory -Force | Out-Null
    }
}

#------------------------------------------------------------------------------------

# Adds a mapping to the `.origin` file.
# It converts full home directory paths to tilde `~` notation for portability.
# param(CurrentPath): The path to the actual file/folder.
# param(OriginalPath): The path to the symbolic link.
function Add-To-OriginMap {
    param(
        [string]$CurrentPath,
        [string]$OriginalPath
    )
    $userHome = $env:USERPROFILE
    $processedCurrentPath = $CurrentPath
    $processedOriginalPath = $OriginalPath

    if ($processedCurrentPath.StartsWith($userHome, [System.StringComparison]::OrdinalIgnoreCase)) {
        $processedCurrentPath = '~' + $processedCurrentPath.Substring($userHome.Length)
    }

    if ($processedOriginalPath.StartsWith($userHome, [System.StringComparison]::OrdinalIgnoreCase)) {
        $processedOriginalPath = '~' + $processedOriginalPath.Substring($userHome.Length)
    }

    Ensure-OriginFile
    $map = Load-OriginMap
    if (-not $map.ContainsKey($CurrentPath)) {
        "$processedCurrentPath|$processedOriginalPath" | Out-File -FilePath $Global:OriginMapPath -Encoding UTF8 -Append
    }
}

#------------------------------------------------------------------------------------

# Reads and parses the `.origin` file.
# It expands any tilde `~` paths into full, absolute paths so the rest of the script can use them.
# returns: A hashtable of all mappings, e.g., @{'C:\dotfiles\file.txt' = 'C:\docs\file.txt'}.
function Load-OriginMap {
    $map = @{}
    if (Test-Path $Global:OriginMapPath) {
        Get-Content $Global:OriginMapPath | ForEach-Object {
            if ($_ -match "^(.*?)\|(.*)$") {
                $keyPath = $matches[1]
                $valuePath = $matches[2]

                if ($keyPath.StartsWith('~')) {
                    $keyPath = Resolve-Path -Path $keyPath | Select-Object -ExpandProperty Path
                }
                if ($valuePath.StartsWith('~')) {
                    $valuePath = Resolve-Path -Path $valuePath | Select-Object -ExpandProperty Path
                }
                
                $map[$keyPath] = $valuePath
            }
        }
    }
    return $map
}

#------------------------------------------------------------------------------------

# Overwrites the `.origin` file with the contents of a given hashtable.
# This is mainly used after a restore operation where some items may have failed and need to be removed from the map.
# param(Map): A hashtable containing the mappings to save.
function Save-OriginMap {
    param([hashtable]$Map)
    Ensure-OriginFile
    if ($Map.Count -eq 0) {
        Set-Content -Path $Global:OriginMapPath -Value '' -NoNewline
        return
    }
    $Map.GetEnumerator() | ForEach-Object {
        "$($_.Key)|$($_.Value)"
    } | Set-Content -Path $Global:OriginMapPath -Encoding UTF8
}

#------------------------------------------------------------------------------------

# Safely creates a symbolic link, handling both files and directories.
# It first attempts to use the modern PowerShell `New-Item` cmdlet and falls back to the legacy `cmd.exe mklink` command if that fails.
# param(LinkPath): The path where the symbolic link should be created.
# param(TargetPath): The path that the link should point to.
# param(IsDirectory): A boolean, $true if the target is a directory.
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
        $link = '"' + $LinkPath + '"'
        $target = '"' + $TargetPath + '"'
        $mklinkArgs = if ($IsDirectory) { "/c mklink /D $link $target" } else { "/c mklink $link $target" }
        $proc = Start-Process -FilePath "cmd.exe" -ArgumentList $mklinkArgs -NoNewWindow -PassThru -Wait -ErrorAction SilentlyContinue
        if (-not $proc -or $proc.ExitCode -ne 0) {
            throw "Failed to create symlink: $LinkPath -> $TargetPath (exit code $($proc.ExitCode))"
        }
    }
}

#------------------------------------------------------------------------------------

# Generates a unique, timestamped path inside the `.backups` directory for an item.
# param(SourcePath): The path of the item to be backed up.
# returns: The full destination path for the backup.
function Get-BackupPath {
    param(
        [Parameter(Mandatory=$true)][string]$SourcePath
    )
    Ensure-BackupRoot
    $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $name = Split-Path -Path $SourcePath -Leaf
    $backupDir = Join-Path -Path $Global:BackupRootPath -ChildPath $timestamp
    if (!(Test-Path $backupDir)) {
        New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
    }
    return (Join-Path -Path $backupDir -ChildPath $name)
}

#------------------------------------------------------------------------------------

# Creates a safe backup of a file or folder by copying it to the `.backups` directory.
# param(SourcePath): The path of the item to back up.
function Backup-Item {
    param(
        [Parameter(Mandatory=$true)][string]$SourcePath
    )
    $dest = Get-BackupPath -SourcePath $SourcePath
    if ($DryRun) {
        Write-Host "Would backup '$SourcePath' -> '$dest'"
        return $dest
    }

    try {
        $item = Get-Item -LiteralPath $SourcePath -ErrorAction Stop
        if ($item.PSIsContainer) {
            Copy-Item -LiteralPath $SourcePath -Destination $dest -Recurse -Force -ErrorAction Stop
        } else {
            $destDir = Split-Path -Path $dest -Parent
            if (!(Test-Path $destDir)) {
                New-Item -Path $destDir -ItemType Directory -Force | Out-Null
            }
            Copy-Item -LiteralPath $SourcePath -Destination $dest -Force -ErrorAction Stop
        }
        Write-Host "Backup created: '$dest'"
        return $dest
    } catch {
        Write-Host "Backup failed for '$SourcePath': $($_.Exception.Message)" -ForegroundColor Yellow
        return $null
    }
}

#------------------------------------------------------------------------------------

# The main logic for the default "move" operation.
# It moves a target item to the working directory, creates a symlink at its original location, and records the action in the `.origin` file.
# param(Path): The path to the file or folder to move and link.
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
            Write-Host "Would backup original at '$OriginalPath'"
            Write-Host "Would move '$OriginalPath' to '$NewPath'"
            Write-Host "Would create symlink at '$OriginalPath'"
            Write-Host "Would record in .origin file"
            return
        }
        
        Backup-Item -SourcePath $OriginalPath
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

#------------------------------------------------------------------------------------

# Handles the `-Restore` operation.
# It reads the `.origin` map and moves every tracked item from the working directory back to its original location, replacing the symlink.
function Restore-From-Origin {
    $map = Load-OriginMap
    $newMap = @{}

    foreach ($pair in $map.GetEnumerator()) {
        $linkedItem = $pair.Key
        $originalPath = $pair.Value

        try {
            if ($DryRun) {
                if (Test-Path $originalPath) {
                    Write-Host "Would backup existing original '$originalPath'"
                    Write-Host "Would remove existing original '$originalPath'"
                }
                Write-Host "Would backup linked item '$linkedItem'"
                Write-Host "Would move '$linkedItem' back to '$originalPath'"
                continue
            }

            if (Test-Path $originalPath) {
                Backup-Item -SourcePath $originalPath | Out-Null
                Remove-Item $originalPath -Force -Recurse
            }

            if (Test-Path $linkedItem) {
                Backup-Item -SourcePath $linkedItem | Out-Null
            }

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

#------------------------------------------------------------------------------------

# Handles the `-Relink` operation.
# It reads the `.origin` map and re-creates all symlinks. This is useful if links are broken or were accidentally deleted.
function Make-Link-From-Origin {
    $map = Load-OriginMap

    foreach ($pair in $map.GetEnumerator()) {
        $itemPath = $pair.Key
        $originalPath = $pair.Value

        try {
            if ($DryRun) {
                if (Test-Path $originalPath) {
                    Write-Host "Would backup existing original '$originalPath'"
                    Write-Host "Would remove existing original '$originalPath'"
                }
                Write-Host "Would create symlink at '$originalPath' -> '$itemPath'"
                continue
            }

            if (Test-Path $originalPath) {
                Backup-Item -SourcePath $originalPath | Out-Null
                Remove-Item $originalPath -Force -Recurse
            }
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

#------------------------------------------------------------------------------------

# Handles the `-Clean` operation.
# This is a destructive action that removes all files tracked in `.origin` from the working directory, and then deletes the `.origin` file itself.
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

#------------------------------------------------------------------------------------

# Handles the `-Link` operation for creating a single, manual link.
# It creates a symlink at the `-Link` path pointing to the `-Source` path and records the mapping in the `.origin` file.
function Create-Manual-Link {
    try {
        $sourceFullPath = Resolve-Path -LiteralPath $Source -ErrorAction Stop
        $sourceItem = Get-Item -LiteralPath $sourceFullPath -ErrorAction Stop

        if ($DryRun) {
            Write-Host "Would create symlink at '$Link' pointing to '$sourceFullPath'"
            return
        }
        
        $linkParentDir = Split-Path -Path $Link -Parent
        if ($linkParentDir -and (-not (Test-Path $linkParentDir))) {
            Write-Host "Creating parent directory: '$linkParentDir'"
            New-Item -Path $linkParentDir -ItemType Directory -Force | Out-Null
        }

        if (Test-Path $Link -PathType Any) {
            Write-Host "Item already exists at link destination '$Link'. Backing it up."
            Backup-Item -SourcePath $Link | Out-Null
            Remove-Item -LiteralPath $Link -Force -Recurse
        }

        $isDir = $sourceItem.PSIsContainer
        New-SafeSymlink -LinkPath $Link -TargetPath $sourceFullPath -IsDirectory:$isDir
        Write-Host "Successfully created link: '$Link' -> '$sourceFullPath'"

        Add-To-OriginMap -CurrentPath $sourceFullPath -OriginalPath $Link
        Write-Host "Link mapping has been added to the .origin file." -ForegroundColor Green
        Write-Host "WARNING: -Restore or -Clean will now affect the original source file '$sourceFullPath'." -ForegroundColor Yellow

    } catch {
        $msg = "Error creating link: $($_.Exception.Message)"
        Write-Host "`n$msg" -ForegroundColor Red
        "$msg`n" | Out-File -FilePath "$env:TEMP\move-symlink-error.log" -Encoding UTF8 -Append
    }
}

#------------------------------------------------------------------------------------
# --- Main Script Logic ---
# Selects the appropriate function to run based on the command-line parameters.
#------------------------------------------------------------------------------------
switch ($PSCmdlet.ParameterSetName) {
    'CreateLink' { Create-Manual-Link }
    'Restore'    { Restore-From-Origin }
    'Relink'     { Make-Link-From-Origin }
    'Clean'      { Clean-OriginLinks }
    'Move' {
        if ($Source) {
            foreach ($p in $Source) {
                Move-And-Link -Path $p
            }
        } else {
            Write-Host "Please provide a command: -Move, -CreateLink, -Restore, -Relink, or -Clean."
        }
    }
    default {
         Write-Host "Please provide a command: -Move, -CreateLink, -Restore, -Relink, or -Clean."
    }
}


Write-Host "`n--- Script Execution Details ---"
Write-Host "ParameterSet: $($PSCmdlet.ParameterSetName)"
if ($Source) { Write-Host "Source: $Source" }
if ($Link) { Write-Host "Link: $Link" }
if ($TargetSubDirectory) { Write-Host "TargetSubDirectory: $TargetSubDirectory" }
Write-Host "Restore: $Restore"
Write-Host "Relink: $Relink"
Write-Host "Clean: $Clean"
Write-Host "DryRun: $DryRun"
Write-Host "WorkingDirectory: $WorkingDirectory"
Write-Host "-----------------------------"
Write-Host "Press Enter to exit..."
Read-Host | Out-Null
