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
    [CmdLetBinding()]
    Param(
        [parameter(ParameterSetName='Get')]
        [ValidateScript(
            {
                $_ -in (Get-CimInstance -Namespace root\dcim\sysman -ClassName DCIM_BiosEnumeration).AttributeName
            }
        )]
        $AttributeName,
        [Parameter(ParameterSetName='List')][Switch]$ListAttributes
    )

    Begin {
        # Test if DCIM support exists
        Try {
            Get-CimInstance -Namespace root\dcim\sysman -ClassName DCIM_BiosEnumeration | Out-Null
        } catch {
            Write-Error "DCIM not supported"
        }
    }

    Process {
        If ($ListAttributes) {
            Get-CimInstance -Namespace root\dcim\sysman -ClassName DCIM_BiosEnumeration | Select-Object -ExpandProperty AttributeName | Sort-Object
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
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$True)][ValidateScript({$_ -in (Get-BiosAttribute -ListAttributes)})][string]$AttributeName,
        [Parameter(Mandatory=$True)]$ValueName,
        $BiosPassword
    )
    Begin {
        #Check if the value is a possible value
        $CurrentAttribute = Get-BiosAttribute -AttributeName $AttributeName
        if ($ValueName -notin $CurrentAttribute.PossibleValuesDescription) {
            Write-Error "Value falls outside of possible values. Can only be one of: $($CurrentAttribute.PossibleValuesDescription)"
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
        $Result = $BiosService.SetBiosAttributes($null,$null,"$AttributeName","$SetToValue",$BiosPassword)
        If ($Result.SetResult[0] -eq 0) {
            Write-Verbose "Succesfully updated attribute value"
        } else {
            Write-Error "Failed to update attribute value"
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

function Set-UEFIBootOrder {
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


