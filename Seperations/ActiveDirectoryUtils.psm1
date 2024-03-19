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

    # Ensure name parts are trimmed to avoid leading/trailing spaces issues
    $nameParts = $employeeName.Trim() -split '\s+'
    $filter = "(&(objectClass=user)"

    if ($nameParts.Count -ge 2) {
        $givenName = $nameParts[0]
        $surname = $nameParts[-1]
        # Include displayName in the filter along with GivenName and sn (surname)
        $filter += "(|(&(GivenName=$givenName)(sn=$surname))(displayName=*$employeeName*))"
    } else {
        # Check both GivenName, sn (surname), and displayName
        $filter += "(|(GivenName=$employeeName)(sn=$employeeName)(displayName=*$employeeName*))"
    }

    if ($jobTitle) {
        $filter += "(Title=*$jobTitle*)"
    }
    if ($location) {
        $filter += "(physicalDeliveryOfficeName=*$location*)"
    }

    $filter += ")"

    try {
        $adUser = Get-ADUser -LDAPFilter $filter -Properties DisplayName, EmailAddress, MobilePhone, Title, Office, Enabled -ErrorAction Stop

        if ($adUser) {
            $email = $adUser.EmailAddress -split ', '| Select-Object -First 1
            return @{
                Status = if ($adUser.Enabled) { "enabled" } else { "disabled" }
                Email = $email
                Mobile = $adUser.MobilePhone
                JobTitle = $adUser.Title
                Location = $adUser.Office
            }
        } else {
            return @{
                Status = "not found in AD"
                Email = $null
                Mobile = $null
                JobTitle = $null
                Location = $null
            }
        }
    } catch {
        return @{
            Status = "Error accessing AD: $($_.Exception.Message)"
            Email = $null
            Mobile = $null
            JobTitle = $null
            Location = $null
        }
    }
}


# Function to find a computer by employee name in the description in AD
function FindComputerByEmployeeName {
    param (
        [Parameter(Mandatory = $true)]
        [string]$employeeName
    )

    # Ensure name parts are trimmed to avoid leading/trailing spaces issues
    $inputNameParts = $employeeName.Trim() -split '\s+'
    $userFilter = "(&(objectClass=user)"
    $searchNames = @()

    if ($inputNameParts.Count -ge 2) {
        # If a full name is provided, use it for filtering and add both parts to searchNames
        $givenName = $inputNameParts[0]
        $surname = $inputNameParts[-1]
        $userFilter += "(|(&(GivenName=$givenName)(sn=$surname))(displayName=*$employeeName*))"
        $searchNames += "$givenName $surname"
    } else {
        # If only a single name part is provided, consider it could be either first or last name
        $userFilter += "(|(GivenName=$employeeName)(sn=$employeeName)(displayName=*$employeeName*))"
        $searchNames += $employeeName
    }

    $userFilter += ")"

    try {
        $adUser = Get-ADUser -LDAPFilter $userFilter -Property DisplayName
        if ($adUser -ne $null) {
            # Parse the display name for potential additional search terms
            $displayNameParts = $adUser.DisplayName.Trim() -split '\s+'
            if ($displayNameParts.Count -ge 2) {
                $searchDisplayName = "$($displayNameParts[0]) $($displayNameParts[1])"
                if (-not $searchNames.Contains($searchDisplayName)) {
                    $searchNames += $searchDisplayName
                }
            } elseif ($displayNameParts.Count -eq 1 -and -not $searchNames.Contains($displayNameParts[0])) {
                $searchNames += $displayNameParts[0]
            }

            $computersFound = @()
            foreach ($name in $searchNames) {
                $computers = Get-ADComputer -Filter "Description -like '$name*'" -Property Name
                if ($computers -ne $null) {
                    $computersFound += $computers
                }
            }

            if ($computersFound.Count -gt 0) {
                return $computersFound | Select-Object -Unique | ForEach-Object { $_.Name }
            } else {
                return "No computers found in AD for the employee"
            }
        } else {
            return "No user found in AD with the specified name"
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

    # Ensure name parts are trimmed to avoid leading/trailing spaces issues
    $nameParts = $employeeName.Trim() -split '\s+'
    $filter = "(&(objectClass=user)"

    if ($nameParts.Count -ge 2) {
        $givenName = $nameParts[0]
        $surname = $nameParts[-1]
        # Check against displayName, GivenName, and sn (surname)
        $filter += "(|(&(GivenName=$givenName)(sn=$surname))(displayName=*$employeeName*))"
    } else {
        # Check against GivenName, sn (surname), and displayName
        $filter += "(|(GivenName=$employeeName)(sn=$employeeName)(displayName=*$employeeName*))"
    }

    $filter += ")"

    try {
        $adUser = Get-ADUser -LDAPFilter $filter -Properties MemberOf
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

    # Ensure name parts are trimmed to avoid leading/trailing spaces issues
    $nameParts = $employeeName.Trim() -split '\s+'
    $filter = "(&(objectClass=user)"
    
    # Check if the employee name contains at least a first name and last name
    if ($nameParts.Count -ge 2) {
        $givenName = $nameParts[0]
        $surname = $nameParts[-1]
        $filter += "(&(GivenName=$givenName)(sn=$surname))"
    } else {
        # If only one part is found, assume it could be either the given name or the surname
        $filter += "(|(GivenName=$employeeName)(sn=$employeeName))"
    }
    
    $filter += ")"

    try {
        $adUser = Get-ADUser -LDAPFilter $filter -Properties PrimaryGroup, DisplayName, EmailAddress, MobilePhone, Title, Office, Enabled

        if ($adUser -ne $null) {
            # Disable the AD account
            Set-ADUser -Identity $adUser -Enabled $false
            Set-ADUser -Identity $adUser -Manager $null
            Set-ADUser -Identity $adUser -Replace @{msExchHideFromAddressLists = $true}

            # Get the primary group
            $primaryGroup = Get-ADGroup -Identity $adUser.PrimaryGroup

            # Remove from all groups except the primary group
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
# Function to move an AD user to the Disabled Accounts OU
function MoveADUserToDisabledOU {
    param (
        [Parameter(Mandatory = $true)]
        [string]$employeeName
    )

    try {
        # Correct distinguished name for the Disabled Accounts OU
        $disabledAccountsOU = "OU=_Disabled Accounts_,DC=Microsoft,DC=Com"

        # Get the AD user object
        $adUser = Get-ADUser -Filter "Name -like '*$employeeName*'" -ErrorAction SilentlyContinue

        if ($adUser) {
            # Move the user to the Disabled Accounts OU
            Move-ADObject -Identity $adUser.DistinguishedName -TargetPath $disabledAccountsOU -ErrorAction SilentlyContinue
            Write-Host "$employeeName has been moved to the Disabled Accounts OU."
        } else {
            Write-Host "AD account for $employeeName not found."
        }
    } catch {
        Write-Host "Error encountered in MoveADUserToDisabledOU: $($_.Exception.Message)"
        
    }
}


# Including the new function in the module export list
Export-ModuleMember -Function 'GetADEmployeeDetails', 'FindComputerByEmployeeName', 'GetADEmployeeGroups', 'DisableAdAccountOnEffectiveDate', 'DisableComputer', 'Get-EffectiveDateTime', 'MoveADUserToDisabledOU'

