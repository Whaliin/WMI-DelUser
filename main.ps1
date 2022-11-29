#echo off
<#
    Description:
        Automatically removes userprofiles the same way that Windows would, using the Win32_UserProfile (WMI instance)
        This means that the next time the user logs on they will not get an error, as opposed to just deleting the folder on disk

    Parameters:
        SpaceLimit will remove until you reach the desired free space threshold on the disk 
        "-SpaceLimit 100" will delete userprofiles until you reach 100GB of free space on disk

        MonthCutoff will remove any userprofiles that havent been used since todays date minus months
        "-MonthCutoff 6" will remove userprofiles that have not been used in the last six months

        "-SpaceLimit 100 -MonthCutoff 6" will remove userprofiles that have not been used in the last six months, until you have 100GB of free space on disk

        WhitelistUser will whitelist any matching username from deletion
        "-WhitelistUser USDOEJ" will not delete the USDOEJ user regardless of space or month limitations. Useful for admin profiles, service accounts or top users.
        If you are going to use this for an organization you can also directly change the $WhitelistUsers < (added s) so you don't have to check this switch every time.

        ProfileLimit will only remove x amount of profiles (used for testing)
        "-ProfileLimit 5" will only remove the first 5 found profiles, in arbitrary order

        The DebugMode switch will enable "safe" mode which will bypass admin checks and not actually delete any userprofiles.

        The Verbose switch will enable verbose logging for some commands (WMI related commands)
#>
param (
    [Alias("L", "Log")][switch]$Verbose, 
    [Alias("ML")][int]$MonthCutoff,
    [Alias("SL", "GB")][int]$SpaceLimit,
    [Alias("DBG", "SAFE")][switch]$DebugMode,
    [Alias("WU", "Whitelist")][string[]]$WhitelistUser,
    [int]$ProfileLimit
)

$LogFile = "C:\Users\DelUser_$(Get-Date -Format "yyyyMMdd_HHmm").log"

function Write-Log {
    param (
        [Parameter(Mandatory, Position=0)][string]$InputStr
    )

    Write-Output $InputStr
    "$("[{0:MM/dd/yy} {0:HH:mm:ss.fffffff}]" -f (Get-Date)) $($InputStr)" *>> $LogFile
}

function Write-Columns {
    param (
        [string]$Header,
        [string[]]$Content,
        [int]$Columns,
        [int]$MaxLength,
        [string]$Div
    )

    if ($Columns -le 0) { $Columns = 5 }
    if ($MaxLength -le 3) { $MaxLength = 16 } 
    if ($Div -eq "") { $Div = " " }

    Write-Log $Header
    $ctr = 0
    $buf = ""
    ForEach($i in $Content) {
        if ($i.Length -gt $MaxLength) {
            $buf += $div + $i.PadRight($MaxLength, " ").Substring(0, $MaxLength-3) + "..."
        } else {
            $buf += $div + $i.PadRight($MaxLength, " ").Substring(0, $MaxLength)
        }
        $ctr += 1

        if ($ctr -eq $Columns) {
            Write-Log $buf
            $buf = ""
            $ctr = 0
        }
    }

    if ($ctr -ne 0) {
        Write-Log $buf
    }
}

Write-Log "<<< Script starting >>>"

#check if admin
if (-not (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    if ($DebugMode) {
        Write-Log "!- Bypass admin check. Can not guarantee script will work as intended."
    } else {
        Throw "You need administrator privileges to use this script."
    }
}

$VerbosePreference = switch ($Verbose) {
  $true    {"Continue"}
  $false   {"SilentlyContinue"}
}

#whitelist some standard directories
$WhitelistUsers = ("")

#process parameters
if ($null -ne $WhitelistUser) {
    ForEach($i in $WhitelistUser) {
        $WhitelistUsers += $i
    }
}

$LocalDisk = Get-PSDrive C 

if ($WhitelistUsers.Count -gt 0) {
    Write-Columns -Header "Whitelisting users:" -Content $WhitelistUsers
}

##########

Write-Log "Deleting TEMP users"
try {
    Get-ChildItem "C:\Users" | Where-Object { $_.Name.StartsWith("TEMP") } | ForEach-Object {
        Write-Log "Deleting $($_.FullName)"
        Remove-Item -path $_.FullName
    }
} catch {
    Write-Log "Failed to delete TEMP folder(s)"
}

if ($MonthCutoff -le 0 -and $SpaceLimit -le 0) {
    Throw "Invalid argument(s)"
} elseif ($MonthCutoff -gt 0) {
    Write-Log "Using last modified mode"

    If ($SpaceLimit -gt 0) {
        Write-Log "Will clear until reaching $($SpaceLimit)GB free, currently $($LocalDisk.Free/1GB) GB free"
    } else {
        Write-Log "Free space on disk: $([Math]::Round($LocalDisk.Free/1GB, 2)) GB"
    }

    #get the cutoff date ($MonthCutoff months ago)
    $CutoffDate = (Get-Date).AddMonths($($MonthCutoff * -1))

    Write-Log "Deleting accounts that have not been used since $($CutoffDate.ToShortDateString())"

    [System.Collections.ArrayList]$SortableUsers = @();

    #Get all Win32_UserProfile, which is NOT tagged Special or Loaded and not in WhitelistUsers
    Get-CimInstance -Class Win32_UserProfile | Where-Object { $_.Special -eq $false -and $_.Loaded -eq $false -and $WhitelistUsers -inotcontains $($_.LocalPath.Substring($_.LocalPath.LastIndexOf("\")+1)) } | ForEach-Object {
        <#
            Recursively get every folder and file accessible under the userfolder, excluding ReparsePoint or System files
            Select only the first object that has been written to after cutoff date and where the name excludes some system modified files
        #>
        $FirstFileFound = Get-ChildItem -Path $_.LocalPath -Force -Attributes !ReparsePoint, !System -Recurse -File -ErrorAction $VerbosePreference | Where-Object { $_.LastWriteTime -gt $CutoffDate -and $_.BaseName -inotin "NTUSER","UsrClass" } | Select-Object -First 1

        if ($null -ne $FirstFileFound) {
            Write-Log "Keeping $($_.LocalPath.Substring($_.LocalPath.LastIndexOf("\")+1)) ($($FirstFileFound.FullName), $($FirstFileFound.LastWriteTime.ToLocalTime()))"
        } else {
            Write-Log "Adding $($_.LocalPath.Substring($_.LocalPath.LastIndexOf("\")+1)) to deletion queue (no file found after date)"
            $obj = [PSCustomObject]@{
                "Username"    = $_.LocalPath.Substring($_.LocalPath.LastIndexOf("\")+1)
                "CimInstance" = $_
            }
            $SortableUsers.Add($obj) | Out-Null
        }
    }

    if ($SortableUsers.Count -gt 0) {
        Write-Log "Beginning delete process..."

        ForEach($i in $SortableUsers) {
            Write-Log "Deleting $($i.Username)"

            if (-not $DebugMode) {
                Remove-CimInstance $i.CimInstance
            }

            if ($SpaceLimit -gt 0 -and $SpaceLimit -le $($LocalDisk.Free/1GB)) {
                Write-Log "Free space exceeds limit ($($SpaceLimit) GB). Exiting"
                break
            } else {
                Write-Log "Free space: $([Math]::Round($LocalDisk.Free/1GB, 2)) GB, continuing"
            }
        }

        if ($SpaceLimit -gt 0 -and $SpaceLimit -gt $($LocalDisk.Free/1GB)) {
            Write-Log "Unable to reach desired space threshold by deleting user profiles"
        } else {
            Write-Log "Finished deleting users"
        }
    } else {
        Write-Log "No valid users found."
    }
#with GB args but no M (just check for storage usage)
} elseif ($SpaceLimit -gt 0 -and $MonthCutoff -le 0) {
    Write-Log "Using free space mode"

    if ($SpaceLimit -gt $($LocalDisk.Free/1GB)) {
        <#
            Ignore special userprofiles (SYSTEM accounts)
            Ignore loaded userprofiles (signed in accounts)
            Check if whitelisted
        #>
        if ($ProfileLimit -gt 0) {
            $userprofiles = Get-CimInstance -Class Win32_UserProfile | Where-Object { $_.Special -eq $false -and $_.Loaded -eq $false -and $WhitelistUsers -inotcontains $($_.LocalPath.Substring($_.LocalPath.LastIndexOf("\")+1)) } | Select-Object -First $ProfileLimit
        } else {
            $userprofiles = Get-CimInstance -Class Win32_UserProfile | Where-Object { $_.Special -eq $false -and $_.Loaded -eq $false -and $WhitelistUsers -inotcontains $($_.LocalPath.Substring($_.LocalPath.LastIndexOf("\")+1)) }
        }
        
        #
        [System.Collections.ArrayList]$SortableUsers = @();

        #
        Write-Log "Getting user directory sizes... This may take a while"
        ForEach($user in $userprofiles) {
            $obj = [PSCustomObject]@{
                "Size"        = [Math]::Round((Get-ChildItem $user.LocalPath -Recurse -Force -Attributes !ReparsePoint -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum / 1GB, 2)
                "Username"    = $user.LocalPath.Substring($user.LocalPath.LastIndexOf("\")+1)
                "CimInstance" = $user
            }
            $SortableUsers.Add($obj) | Out-Null
        }

        Write-Log "Done getting user directory sizes"
        #Sort the array by size
        $SortableUsers = $SortableUsers | Sort-Object -Property Size -Descending 

        ForEach($i in $SortableUsers) {
            Write-Log "Deleting $($i.Username) ($($i.Size) GB)"
            if (-not $DebugMode) {
                Remove-CimInstance $i.CimInstance
            }

            if ($SpaceLimit -le $($LocalDisk.Free/1GB)) {
                Write-Log "Free space exceeds limit ($($SpaceLimit) GB)"
                break
            } else {
                Write-Log "Free space: $([Math]::Round($LocalDisk.Free/1GB, 2)) GB, continuing"
            }
        }

        if ($SpaceLimit -gt $($LocalDisk.Free/1GB)) {
            Write-Log "Unable to reach desired space threshold by deleting user profiles"
        } else {
            Write-Log "Free space ($([Math]::Round($LocalDisk.Free/1GB, 2)) GB)"
        }
    } else {
        Write-Log "Free space ($([Math]::Round($LocalDisk.Free/1GB, 2))GB) already exceeds limit ($($SpaceLimit)GB)"
    }
}

Write-Log "--- Script EOF ---"
