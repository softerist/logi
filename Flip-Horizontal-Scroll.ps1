[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Automatic')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Explicit')]
    [string]$InstanceId,

    [Parameter(Mandatory, ParameterSetName = 'Guided')]
    [switch]$Identify,

    [ValidateSet(0, 1)]
    [int]$Value = 1,

    [switch]$RestartDevice
)

function Get-ConnectedMouse {
    Get-PnpDevice -PresentOnly -ErrorAction Stop | Where-Object Class -eq 'Mouse'
}

function Read-MouseDeviceProperty {
    param([string[]]$Ids, [hashtable]$Cache)

    $keys = @(
        'DEVPKEY_NAME'
        'DEVPKEY_Device_BusReportedDeviceDesc'
        'DEVPKEY_Device_Parent'
        'DEVPKEY_Device_ContainerId'
    )
    foreach ($id in $Ids) {
        $Cache[$id] = @{}
    }

    foreach ($property in Get-PnpDeviceProperty -InstanceId $Ids -KeyName $keys -WhatIf:$false -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable propertyErrors) {
        $Cache[$property.InstanceId][$property.KeyName] = $property.Data
    }
    if ($propertyErrors) {
        Write-Verbose "Some optional device properties were unavailable. $($propertyErrors[0].Exception.Message)"
    }
}

function Find-MxMasterMouse {
    param([object[]]$Mice)

    $modelPattern = '\bMX[\s-]+Master[\s-]+4\b'
    $cache = @{}
    Read-MouseDeviceProperty -Ids $Mice.InstanceId -Cache $cache

    foreach ($mouse in $Mice) {
        $id = $mouse.InstanceId
        $node = $cache[$id]
        $names = @($mouse.FriendlyName, $node['DEVPKEY_NAME'], $node['DEVPKEY_Device_BusReportedDeviceDesc'])
        if ($names -match $modelPattern) {
            $mouse
            continue
        }

        # Walk parents only while they belong to the same physical device.
        $container = ([string]$node['DEVPKEY_Device_ContainerId']).Trim([char[]]'{}')
        if (!$container -or $container -in @([string][guid]::Empty, '00000000-0000-0000-ffff-ffffffffffff')) {
            continue
        }

        $visited = @{ $id = $true }
        $parent = [string]$node['DEVPKEY_Device_Parent']
        while ($parent -and !$visited.ContainsKey($parent)) {
            $visited[$parent] = $true
            if (!$cache.ContainsKey($parent)) {
                Read-MouseDeviceProperty -Ids $parent -Cache $cache
            }

            $node = $cache[$parent]
            $parentContainer = ([string]$node['DEVPKEY_Device_ContainerId']).Trim([char[]]'{}')
            if ($parentContainer -ne $container) {
                break
            }

            if (@($node['DEVPKEY_NAME'], $node['DEVPKEY_Device_BusReportedDeviceDesc']) -match $modelPattern) {
                $mouse
                break
            }
            $parent = [string]$node['DEVPKEY_Device_Parent']
        }
    }
}

function Find-ReconnectedMouse {
    param([object[]]$Connected, [switch]$BoltReceiver)

    $disconnectInstruction = 'Disconnect the MX Master 4 or unplug its Bolt receiver'
    if ($BoltReceiver) {
        $disconnectInstruction = 'Unplug the USB Bolt receiver used by your MX Master 4'
    }

    while ($true) {
        $answer = Read-Host "$disconnectInstruction. Press Enter to check or Q to cancel"
        if ($null -eq $answer -or $answer.Trim() -eq 'Q') {
            return
        }
        $disconnected = @(Get-ConnectedMouse)
        $disconnectedIds = @(foreach ($mouse in $disconnected) { $mouse.InstanceId })
        $removed = @($Connected | Where-Object InstanceId -notin $disconnectedIds)
        $unexpected = @($disconnected | Where-Object InstanceId -notin $Connected.InstanceId)
        if ($removed.Count -gt 1 -or $unexpected.Count -gt 0) {
            throw 'Other mouse interfaces changed too. Reconnect your devices and try again with only the MX Master 4 or its receiver.'
        }
        if ($removed.Count -eq 1) {
            break
        }
        Write-Warning "Windows still sees the same mouse interfaces. $disconnectInstruction, then try again."
    }

    $reconnectInstruction = 'Reconnect the mouse or plug its receiver back into the same USB port'
    if ($BoltReceiver) {
        $reconnectInstruction = 'Plug the Bolt receiver back into the same USB port'
    }
    while ($true) {
        $answer = Read-Host "$reconnectInstruction. Press Enter to check or Q to cancel"
        if ($null -eq $answer -or $answer.Trim() -eq 'Q') {
            return
        }
        $reconnected = @(Get-ConnectedMouse)
        $reconnectedIds = @(foreach ($mouse in $reconnected) { $mouse.InstanceId })
        $returned = @($reconnected | Where-Object InstanceId -notin $disconnectedIds)
        $lost = @($disconnected | Where-Object InstanceId -notin $reconnectedIds)
        if ($returned.Count -gt 1 -or $lost.Count -gt 0 -or
            ($returned.Count -eq 1 -and $returned[0].InstanceId -ne $removed[0].InstanceId)) {
            throw 'Windows found a different set of mouse interfaces. Reconnect to the same USB port and try again, or specify the mouse with -InstanceId.'
        }
        if ($returned.Count -eq 1) {
            return $returned[0]
        }
        Write-Warning "Windows has not detected the mouse again yet. $reconnectInstruction, wait a moment, then try again."
    }
}

function Confirm-ScrollChange {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Target, [string]$Action)

    $PSCmdlet.ShouldProcess($Target, $Action)
}

$global:LASTEXITCODE = 0
try {
    Write-Information 'Looking for the MX Master 4 among connected Windows mouse interfaces.' -InformationAction Continue
    $presentMice = @(Get-ConnectedMouse)
    if ($presentMice.Count -eq 0) {
        throw 'Windows reports no connected mouse interfaces.'
    }

    if ($InstanceId) {
        $candidates = @($presentMice | Where-Object InstanceId -eq $InstanceId)
        $method = 'explicit instance ID'
    } else {
        $candidates = @()
        if (!$Identify) {
            $candidates = @(Find-MxMasterMouse -Mice $presentMice)
            $method = 'MX Master 4 device name'
        }

        # Windows exposes this Bolt receiver as a generic mouse interface.
        $boltPattern = '^HID\\VID_046D&PID_C548(?:&|\\)'
        $useBolt = !$Identify -and $candidates.Count -eq 0 -and ($presentMice.InstanceId -match $boltPattern)
        if ($Identify -or $useBolt) {
            $candidates = @(Find-ReconnectedMouse -Connected $presentMice -BoltReceiver:$useBolt)
            if ($candidates.Count -eq 0) {
                Write-Information 'Canceled before applying any changes.' -InformationAction Continue
                return
            }
            if ($useBolt -and $candidates[0].InstanceId -notmatch $boltPattern) {
                throw 'The interface you reconnected belongs to a different mouse. Try again with the USB Bolt receiver for your MX Master 4.'
            }
            $method = 'disconnect and reconnect'
        }
    }

    if ($candidates.Count -eq 0) {
        Write-Verbose "Connected mouse IDs: $($presentMice.InstanceId -join ', ')"
        throw 'Windows could not identify the mouse. Reconnect it and try again, or run the local script with -Identify.'
    }

    if ($candidates.Count -gt 1) {
        Write-Verbose "Matching mouse IDs: $($candidates.InstanceId -join ', ')"
        throw 'Windows found more than one matching mouse. Run the local script with -Identify or select it with -InstanceId.'
    }

    $name = 'FlipFlopHScroll'
    $selectedId = $candidates[0].InstanceId
    $key = "HKLM:\SYSTEM\CurrentControlSet\Enum\$selectedId\Device Parameters"
    Write-Information "Found $selectedId using $method." -InformationAction Continue
    Write-Information "Checking for $name at $key" -InformationAction Continue
    $properties = Get-ItemProperty -LiteralPath $key -ErrorAction Stop

    $current = $null
    if ($null -ne $properties) {
        $current = $properties.PSObject.Properties[$name]
    }

    $needsWrite = $null -eq $current -or $current.Value -isnot [int] -or $current.Value -ne $Value
    if (!$needsWrite) {
        Write-Information "$name already exists with value '$($current.Value)'. Skipping registry write." -InformationAction Continue
        if (!$RestartDevice) {
            return
        }
    }

    $action = 'Restart mouse interface'
    if ($needsWrite) {
        $action = "Set $name to DWORD $Value and restart mouse interface"
    }
    if (!(Confirm-ScrollChange -Target $selectedId -Action $action)) {
        return
    }

    $pnpUtil = (Get-Command -Name (Join-Path $env:SystemRoot 'System32\pnputil.exe') -CommandType Application -ErrorAction Stop).Path
    if (-not (& $pnpUtil /? | Select-String -SimpleMatch '/restart-device' -Quiet)) {
        throw 'This Windows version does not provide PnPUtil /restart-device. Automatic device restart requires Windows 10 version 2004 or newer.'
    }

    # Verify the selected interface is still connected before changing its settings.
    $verified = Get-PnpDevice -InstanceId $selectedId -PresentOnly -ErrorAction Stop
    if ($null -eq $verified -or $verified.Class -ne 'Mouse' -or $verified.InstanceId -ne $selectedId) {
        throw 'The selected mouse interface is no longer present.'
    }

    if ($needsWrite) {
        Set-ItemProperty -LiteralPath $key -Name $name -Type DWord -Value $Value -Confirm:$false -ErrorAction Stop
        Write-Information "Saved $name as DWORD $Value." -InformationAction Continue
    }

    Write-Information "Restarting mouse interface $selectedId." -InformationAction Continue
    try {
        $restartOutput = & $pnpUtil /restart-device $selectedId
        $restartExitCode = $LASTEXITCODE
        foreach ($line in $restartOutput) {
            Write-Information $line -InformationAction Continue
        }
        if ($restartExitCode -eq 3010) {
            Write-Warning 'Windows reports that a reboot is required to finish the device restart.'
        } elseif ($restartExitCode -ne 0) {
            throw "PnPUtil returned exit code $restartExitCode."
        }
    } catch {
        throw "Could not restart the mouse interface. Run the script as administrator with -RestartDevice to retry. $($_.Exception.Message)"
    }
}
catch {
    $global:LASTEXITCODE = 1
    if ($PSBoundParameters['ErrorAction'] -eq 'Stop') {
        throw
    }

    $reason = $_.Exception.Message
    if ($_.CategoryInfo.Category -in @('PermissionDenied', 'SecurityError')) {
        Write-Verbose $reason
        $reason = 'Administrator access is required. Open PowerShell as Administrator and run the command again.'
    }
    Write-Warning "Could not finish: $reason"
}
