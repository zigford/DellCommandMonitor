function Get-DellBiosSetupPasswordState {
    [CmdLetBinding()]
    Param()
    $Query = 'Select * from DCIM_BiosPassword Where AttributeName = "AdminPwd"'
    (Get-WmiObject -Namespace root\dcim\sysman -Query $Query).IsSet
}

function Get-DellBiosBootPasswordState {
    [CmdLetBinding()]
    Param()
    $Query = 'Select * from DCIM_BiosPassword Where AttributeName = "SystemPwd"'
    (Get-WmiObject -Namespace root\dcim\sysman -Query $Query).IsSet
}

function Set-DellBiosPassword {
    [CmdLetBinding()]
    Param($NewPassword="",$OldPassword="")
    Try {
        $Service = Get-WmiObject -Namespace Root\DCIM\Sysman -Class DCIM_BiosService -ErrorAction Stop
    } Catch {
        Write-Error "Unable to attach to DCIM_BiosService: $($_.Exception.Message)" -ErrorAction Stop 
    }
    If ($Service) {
        $Result = $Service.SetBIOSAttributes($null,$null,"AdminPwd",$NewPassword,$OldPassword)
    }
    If ($Result) {
        $Result.SetResult | ForEach-Object {
            if ($_ -eq 0 ) {
                Write-Verbose "Succesfully set new bios setup password"
            } Else {
                Write-Error "Failed to set new bios password: Result $($Result.SetResult)" -ErrorAction Stop
            }
        } 
    } else {
        Write-Error "Failed to set new bios password: Result $($Result.SetResult)" -ErrorAction Stop
    }
}

function Get-BiosAttribute {
    <#
    .SYNOPSIS
        Display bios attributes using Dell Command | Monitor
    .DESCRIPTION
        List available bios attributes which can be set, or display a single attribute, its current value and possible values
    .PARAMETER ListAttributes
        Return a list of attributes available on the current system
    .PARAMETER AttributeName
        Return the current value of the attribute, it's possible values and their descriptions
    .EXAMPLE
        PS> Get-BiosAttribue -AttributeName "Auto on Tuesday"

        AttributeName             : Auto on Tuesday
        CurrentSettingDescription : Disable
        CurrentValue              : {2}
        PossibleValuesDescription : {Enable, Disable}
        PossibleValues            : {1, 2}
    .EXAMPLE
        PS> Get-BiosAttribue -ListAvaialable

        AC Power Recovery Mode
        Admin Setup Lockout
        Advanced Battery Charging Mode
        Always Allow Dell Docks
        Attempt Legacy Boot
        Auto On
    .NOTES
        Author: Jesse Harris
        Version: 1.0
    .LINK
        https://github.com/zigford/DellCommandMonitor
    #>
    [CmdLetBinding(DefaultParameterSetName='Get')]
    Param(
        [parameter(ParameterSetName='Get')]
        [parameter(Position=0)]
        [ValidateScript(
            {
                If (-not $Global:BiosAttributeList) {
                    $Global:BiosAttributeList = (Get-CimInstance -Namespace root\dcim\sysman -ClassName DCIM_BiosEnumeration).AttributeName | Sort-Object
                }
                $_ -in $Global:BiosAttributeList
            }
        )]
        $AttributeName,
        [Parameter(ParameterSetName='List')][Switch]$ListAttributes
    )

    Begin {
        # Test if DCIM support exists
        If (-Not $Global:BiosAttributeList) {
            Try {
                $Global:BiosAttributeList = Get-CimInstance -Namespace root\dcim\sysman -ClassName DCIM_BiosEnumeration | Select-Object -Expand AttributeName | Sort-Object
            } catch {
                Write-Error "DCIM not supported"
            }
        }
    }

    Process {
        If ($ListAttributes) {
            $Global:BiosAttributeList
        } else {
            $AttributeValue = Get-CimInstance -Namespace root\dcim\sysman -ClassName DCIM_BiosEnumeration | Where-Object {$_.AttributeName -eq $AttributeName} 
            $CurrentValue = $AttributeValue.CurrentValue
            $PossibleValueIndex = for ($i=0;$i -lt $AttributeValue.PossibleValues.Count;$i++) { If ($AttributeValue.PossibleValues[$i] -eq $CurrentValue) {$i}}
            $ValueDescription = $AttributeValue.PossibleValuesDescription[$PossibleValueIndex]
            [PSCustomObject]@{
                'AttributeName' = $AttributeName
                'CurrentSettingDescription' = $ValueDescription
                'CurrentValue' = $CurrentValue
                'PossibleValuesDescription' = $AttributeValue.PossibleValuesDescription
                'PossibleValues' = $AttributeValue.PossibleValues
            }
        }
    }
}

function Set-BiosAttribute {
    <#
    .SYNOPSIS
        Set a bios attribute
    .DESCRIPTION
        Set bios attributes to a possible value using the Dell Command | Monitor cim system
    .PARAMETER AttributeName
        Specify the bios attribute to set
    .PARAMETER ValueName
        Specify the name of the value to set. Obtained using Get-BiosAttribute -AttributeName 
    .PARAMETER Whatif
        Shows what would happen if the cmdlet runs. The cmdlet is not run.
    .EXAMPLE
        # Enable bios auto on, for Tuesday and Friday
        PS>  'Tuesday','Friday'|%{Set-BiosAttribute -AttributeName "Auto on $_" Enable -BiosPassword password}
    .EXAMPLE
        # Use whatif to test what would happen when setting the Auto On hour to 3
        PS> Set-BiosAttribute 'Auto On Hour' -ValueName 3 -Whatif
        What if: Performing the operation "SetBiosAttribute" on target Auto On Hour. 
    .NOTES
        Author: Jesse Harris

    .LINK
        https://github.com/zigford/DellCommandMonitor
    #>
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$True)][ValidateScript({$_ -in (Get-BiosAttribute -ListAttributes)})][string]$AttributeName,
        [Parameter(Mandatory=$True)]$ValueName,
        [switch]$Whatif=$False,
        $BiosPassword
    )
    Begin {
        #Check if the value is a possible value
        $CurrentAttribute = Get-BiosAttribute -AttributeName $AttributeName
        if ($CurrentAttribute.PossibleValuesDescription.Count -eq 1) {
            $PossibleRange = $CurrentAttribute.PossibleValuesDescription.Split('-')[0]..$CurrentAttribute.PossibleValuesDescription.Split('-')[1]
            if ($ValueName -notin $PossibleRange) {
                Write-Error "Value falls outside of possible range. Can only be between $($CurrentAttribute.PossibleValuesDescription)"
            }
        } else {
            if ($ValueName -notin $CurrentAttribute.PossibleValuesDescription) {
                Write-Error "Value falls outside of possible values. Can only be one of: $($CurrentAttribute.PossibleValuesDescription)"
            }
        }
    }

    Process {
        # Calculate what the Value number will be.
        for ($i=0;$i -lt $CurrentAttribute.PossibleValuesDescription.Count;$i++) {
            If ($CurrentAttribute.PossibleValuesDescription[$i] -eq $ValueName) {
                $SetToValue = $CurrentAttribute.PossibleValues[$i]
            }
        }
        Write-Verbose "Setting Attribute $AttributeName to value $SetToValue"
        $BiosService = Get-WMIObject -Namespace root\dcim\sysman -Class DCIM_BiosService
        If ($Whatif) {
            Write-Host "What if: Performing the operation ""SetBiosAttribute"" on target $AttributeName."
        } else {
            $Result = $BiosService.SetBiosAttributes($null,$null,"$AttributeName","$SetToValue",$BiosPassword)
            If ($Result.SetResult[0] -eq 0) {
                Write-Verbose "Succesfully updated attribute value"
            } else {
                Write-Error "Failed to update attribute value. Check password"
            }
        }
    }
}

function Get-CurrentBootMode {
    [CmdLetBinding()]
    Param()
    Begin{}
    Process {
        Get-WmiObject -Namespace root\dcim\sysman -Class DCIM_ElementSettingData | ForEach-Object {
            if ($_.IsCurrent -eq 0) {
                'BIOS'
            } ElseIf ($_.IsCurrent -eq 1) {
                If ($_.SettingData -match 'DCIM:BootConfigSetting:Next:2') {
                    'UEFI'
                } else {
                    'BIOS'
                } 
            }
        }
    }
}

function Get-BootOrderObject {
    [CmdLetBinding()]
    Param(
        [ValidateSet(
            'UEFI',
            'BIOS'
        )]
        [String]$BootOrderType
    )
    Begin {}
    Process {
        $OrderedComponent = Get-WmiObject -namespace root\dcim\sysman -Class dcim_orderedcomponent 
        Switch ($BootOrderType) {
            'UEFI' {$OrderedComponent | Where-Object {$_.partcomponent -match 'BootListType-2'} }
            'BIOS' {$OrderedComponent | Where-Object {$_.partcomponent -match 'BootListType-1'} }
        }
    }
}

function Get-BootOrder {
    [CmdLetBinding()]
    Param()
    Begin {
    }
    Process {
        $CurrentBootOrder = Get-BootOrderObject -BootOrderType (Get-CurrentBootMode) | ForEach-Object {
            $PartComponent = $_.PartComponent
            $PartComponentMatch = $PartComponent.Replace('/','\\')
            $Query = "Select * from DCIM_BootSourceSetting Where __PATH = '" + $PartComponentMatch + "'"
            [PSCustomObject]@{
                'AssignedSequence' = $_.AssignedSequence
                'BiosBootString' = (Get-WmiObject -Namespace root\dcim\sysman -query $Query).BiosBootString
                'PartComponent' = $PartComponent
            }
        }
        $CurrentBootOrder
    }
}

function Get-UEFIBootOrder {
    [CmdLetBinding()]
    Param()
    Begin {
        if (-Not (Get-BootOrderObject -BootOrderType UEFI)) {
            Write-Verbose "No UEFI Boot list configured"
            break
        } 
    }
    Process {
        $CurrentBootOrder = Get-BootOrderObject -BootOrderType UEFI | ForEach-Object {
            $PartComponent = $_.PartComponent
            $PartComponentMatch = $PartComponent.Replace('/','\\')
            $Query = "Select * from DCIM_BootSourceSetting Where __PATH = '" + $PartComponentMatch + "'"
            [PSCustomObject]@{
                'AssignedSequence' = $_.AssignedSequence
                'BiosBootString' = (Get-WmiObject -Namespace root\dcim\sysman -query $Query).BiosBootString
                'PartComponent' = $PartComponent
            }
        }
        $CurrentBootOrder
    }
}

function New-BootOrder {
    [CmdLetBinding()]
        Param(
            [ValidateScript({
                if ($_ -notin (Get-BootOrder).BiosBootString) {
                    throw "Enter valid boot order strings. Obtain valid strings using the Get-BootOrder cmdlet"
                } else {
                    $true
                }
            })]
        [string]$Order
        )
    Begin {}
    Process {
        ForEach ($BootItem in $Order) {
            Get-BootOrder | Where-Object {$_.BiosBootString -eq $BootItem}
        }
        
    }
}

function New-UEFIBootOrder {
    [CmdLetBinding()]
    Param(
        [ValidateSet(
            'Windows Boot Manager',
            'Onboard NIC(IPV4)',
            'Onboard NIC(IPV6)',
            'USB NIC(IPV4)',
            'USB NIC(IPV6)'
            )]
        [string[]]$Order
        )
    Begin {}
    Process {
        ForEach ($BootItem in $Order) {
            Get-UEFIBootOrder | Where-Object {$_.BiosBootString -eq $BootItem}
        }
        
    }
}

function Get-BootConfigObject {
    [CmdLetBinding()]
    Param(
        [ValidateSet(
            'UEFI',
            'BIOS'
        )]$BootConfigType
    )
    Process {
        $cbo = Get-WmiObject -namespace root\dcim\sysman -class dcim_bootconfigsetting
        Switch ($BootConfigType) {
            'UEFI' { $cbo | Where-Object { $_.InstanceID -eq 'DCIM:BootConfigSetting:Next:2' }}
            'BIOS'  { $cbo | Where-Object { $_.InstanceID -eq 'DCIM:BootConfigSetting:Next:1' }}
        }
    }
}

function Set-BootOrder {
[CmdLetBinding()]
    Param(
        [ValidateScript(
            {
                if ($_.PartComponent) {
                    $True
                } Else {
                    Throw "Not a valid boot order"
                }
            }
        )]$BootOrder,
        [string]$BiosPassword,
        [switch]$SuspendBitlocker
    )
    Begin {
        if (-Not (Get-BootOrderObject -BootOrderType (Get-CurrentBootMode))) {
            Write-Verbose "No Boot list configured"
            break
        } 
    }
    Process {
        $BootOrderArray = $BootOrder | ForEach-Object {$_.PartComponent}
        If ($SuspendBitlocker) {
            $Bitlocker = Get-BitLockerVolume -MountPoint $env:SystemDrive
            If ($Bitlocker.ProtectionStatus.ToString() -eq 'On') {
                Write-Verbose 'Suspending Bitlocker'
                Suspend-BitLocker -MountPoint $env:SystemDrive -ErrorAction Stop | Out-Null
                Write-Verbose 'Bitlocker Suspended'
            } Else {
                Write-Verbose 'Bitlocker protections already disabled'
            }
        }
        Write-Verbose 'Setting new boot order'
        $Result = (Get-BootConfigObject -BootConfigType (Get-CurrentBootMode)).changebootorder($BootOrderArray, $BiosPassword)
        If ($Result.ReturnValue -eq 0) {
            Write-Verbose 'Succesfully set new boot order'
            Get-BootOrder
        } else {
            Write-Error "Failed to set new boot order"
        }
    }
}

function Set-UEFIBootOrder {
   <#
   .SYNOPSIS
   Set boot order of a UEFI configured Dell PC with Dell Command | Monitor installed
   
   .DESCRIPTION
   Using the Sysman\DCIM namespace that Dell Command | Monitor makes available, set the boot order using the changebootorder method of the dcim_bootconfigsetting class
   
   .PARAMETER BootOrder
   An array of strings matching valid boot order strings. Valid values can be obtained using the Get-UEFIBootOrder cmdlet
   
   .PARAMETER BiosPassword
   Blank if no bios password is set, otherwise set this or the command will fail.
   
   .PARAMETER SuspendBitlocker
   If Bitlocker is enabled, it would be wise to suspend it for the next boot in order to avoid triggering bitlocker recovery mode.
   
   .EXAMPLE
   PS> Set-UEFIBootOrder -BiosPassword 'mumstheword' -BootOrder (New-UEFIBootOrder -Order 'Onboard NIC(IPV4)') -SuspendBitlocker

   Set's the Onboard Nic to be the first boot object. In this case any boot objects not specified are effectivly disabled. A saner option would be to put 'Windows Boot Manager' second
   
   .NOTES
   Written with much love by Jesse Harris
   #>  
    [CmdLetBinding()]
    Param(
        [ValidateScript(
            {
                if ($_.PartComponent) {
                    $True
                } Else {
                    Throw "Not a valid boot order"
                }
            }
        )]$BootOrder,
        [string]$BiosPassword,
        [switch]$SuspendBitlocker
    )
    Begin {
        if (-Not (Get-BootOrderObject -BootOrderType UEFI)) {
            Write-Verbose "No UEFI Boot list configured"
            break
        } 
    }
    Process {
        $BootOrderArray = $BootOrder | ForEach-Object {$_.PartComponent}
        If ($SuspendBitlocker) {
            $Bitlocker = Get-BitLockerVolume -MountPoint $env:SystemDrive
            If ($Bitlocker.ProtectionStatus.ToString() -eq 'On') {
                Write-Verbose 'Suspending Bitlocker'
                Suspend-BitLocker -MountPoint $env:SystemDrive -ErrorAction Stop | Out-Null
                Write-Verbose 'Bitlocker Suspended'
            } Else {
                Write-Verbose 'Bitlocker protections already disabled'
            }
        }
        Write-Verbose 'Setting new boot order'
        $Result = (Get-BootConfigObject -BootConfigType UEFI).changebootorder($BootOrderArray, $BiosPassword)
        If ($Result.ReturnValue -eq 0) {
            Write-Verbose 'Succesfully set new boot order'
            Get-UEFIBootOrder
        } else {
            Write-Error "Failed to set new boot order"
        }
    }
}