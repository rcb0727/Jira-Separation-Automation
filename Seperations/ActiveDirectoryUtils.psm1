##ActiveDirectoryUtils

function Get-EffectiveDateTime {
    param (
        [string]$effectiveDate,
        [int]$offsetHours
    )

    $effectiveDateTime = [DateTime]::ParseExact($effectiveDate, 'MM/dd/yyyy', $null).AddHours($offsetHours)
    return $effectiveDateTime
}

# Function to check employee status in Active Directory and get additional details
function GetADEmployeeDetails {
    param (
        [Parameter(Mandatory = $true)]
        [string]$employeeName,
        [string]$jobTitle,
        [string]$location
    )

    try {
        # Split the name to handle cases with and without middle names.
        $nameParts = $employeeName -split ' '
        $filter = "(&(objectClass=user)"

        # Add name parts to filter. Handle users with just first and last names or with middle names.
        if ($nameParts.Count -ge 2) {
            $givenName = $nameParts[0]
            $surname = $nameParts[-1]
            $filter += "(|(GivenName=*$givenName*)(Surname=*$surname*))"
        }

        # Add job title and location to filter if provided.
        if ($jobTitle) {
            $filter += "(Title=*$jobTitle*)"
        }
        if ($location) {
            $filter += "(Office=*$location*)"
        }

        $filter += ")"
        
        $adUser = Get-ADUser -LDAPFilter $filter -Properties "DisplayName", "EmailAddress", "MobilePhone", "Title", "Office", "Enabled"

        if ($adUser) {
            $firstEmail = $adUser.EmailAddress -split ', ' | Select-Object -First 1
            return @{
                'Status' = if ($adUser.Enabled) { "enabled" } else { "disabled" }
                'Email' = $firstEmail
                'Mobile' = $adUser.MobilePhone
                'JobTitle' = $adUser.Title
                'Location' = $adUser.Office
            }
        } else {
            return @{
                'Status' = "not found in AD"
                'Email' = $null
                'Mobile' = $null
                'JobTitle' = $null
                'Location' = $null
            }
        }
    } catch {
        return @{
            'Status' = "Error accessing AD: $($_.Exception.Message)"
            'Email' = $null
            'Mobile' = $null
            'JobTitle' = $null
            'Location' = $null
        }
    }
}



# Function to find a computer by employee name in the description in AD
function FindComputerByEmployeeName {
    param (
        [Parameter(Mandatory = $true)]
        [string]$employeeName
    )
    try {
        $computers = Get-ADComputer -Filter "Description -like '*$employeeName*'" -Property Name
        if ($computers -ne $null) {
            return $computers | ForEach-Object { $_.Name }
        } else {
            return "No computers found in AD"
        }
    } catch {
        return "Error searching AD for computers: $($_.Exception.Message)"
    }
}

# Function to get all AD groups for a given employee
function GetADEmployeeGroups {
    param (
        [Parameter(Mandatory = $true)]
        [string]$employeeName
    )
    try {
        $adUser = Get-ADUser -Filter "Name -like '*$employeeName*'" -Properties MemberOf
        if ($adUser -ne $null -and $adUser.MemberOf -ne $null) {
            $groupDns = $adUser.MemberOf
            $groups = $groupDns | ForEach-Object { (Get-ADGroup -Identity $_).Name }
            return $groups -join "; "
        } else {
            return "No groups found for this user in AD"
        }
    } catch {
        return "Error fetching groups from AD: $($_.Exception.Message)"
    }
}

# Function to disable AD account on effective date
function DisableAdAccountOnEffectiveDate {
    param (
        [Parameter(Mandatory = $true)]
        [string]$employeeName
    )

    try {
        $adUser = Get-ADUser -Filter "Name -like '*$employeeName*'" -Properties PrimaryGroup
        if ($adUser -ne $null) {
            # Disable the AD account
            Set-ADUser -Identity $adUser -Enabled $false
            Set-ADUser -Identity $adUser -Manager $null
            Set-ADUser -Identity $adUser -Replace @{msExchHideFromAddressLists = $true}

            # Get the primary group
            $primaryGroup = Get-ADGroup -Identity $adUser.PrimaryGroup

            # Remove from all groups except primary group
            Get-ADUser -Identity $adUser | Get-ADPrincipalGroupMembership | Where-Object { $_.DistinguishedName -ne $primaryGroup.DistinguishedName } | ForEach-Object { Remove-ADGroupMember -Identity $_ -Members $adUser -Confirm:$false }

            return @{
                'Result' = "Success"
                'Message' = "AD account for $employeeName has been disabled and removed from all AD groups."
            }
        } else {
            return @{
                'Result' = "NotFound"
                'Message' = "AD account for $employeeName not found."
            }
        }
    } catch {
        Write-Host "Error encountered in DisableAdAccountOnEffectiveDate: $($_.Exception.Message)"
        return @{
            'Result' = "Error"
            'Message' = "Error disabling AD account for $employeeName $($_.Exception.Message)"
        }
    }
}



# Function to disable a computer account
function DisableComputer {
    param (
        [Parameter(Mandatory = $true)]
        [string]$employeeName
    )

    try {
        $computerName = FindComputerByEmployeeName -employeeName $employeeName
        if ($computerName) {
            # Disable the computer account
            Set-ADComputer -Identity $computerName -Enabled $false
            return " Computer has been disabled."
        } else {
            return " No Computer found."
        }
    } catch {
        return "$($_.Exception.Message)"
    }
}



Export-ModuleMember -Function 'GetADEmployeeDetails', 'FindComputerByEmployeeName', 'GetADEmployeeGroups', 'DisableAdAccountOnEffectiveDate', 'DisableComputer', 'Get-EffectiveDateTime'

