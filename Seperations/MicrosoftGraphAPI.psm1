# MicrosoftGraphAPI

# Authentication for Microsoft Graph API
function Get-IntuneAccessToken {
    $authority = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
    $authBody = @{
        "grant_type" = "client_credentials"
        "client_id" = $clientId
        "client_secret" = $clientSecret
        "scope" = $scope
    }

    try {
        $authResponse = Invoke-RestMethod -Method Post -Uri $authority -Body $authBody
        return $authResponse.access_token
    } catch {
        Write-Warning "Failed to get access token: $($_.Exception.Message)"
        exit
    }
}

# Function to get device details from Intune
function Get-IntuneDeviceDetails {
    param (
        [Parameter(Mandatory = $true)]
        [string]$emailAddress
    )

    $accessToken = Get-IntuneAccessToken
    if (-not $accessToken) {
        return "Failed to obtain access token."
    }

    $headers = @{
        "Authorization" = "Bearer $accessToken"
        "Accept" = "application/json"
    }

    $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$filter=userPrincipalName eq '$emailAddress' and operatingSystem eq 'iOS'&`$select=id,deviceName,serialNumber"

    try {
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
        $deviceDetails = @()
        foreach ($device in $response.value) {
            $deviceDetails += @{
                "DeviceName" = $device.deviceName
                "SerialNumber" = $device.serialNumber
                "ManagedDeviceId" = $device.id
            }
        }

        if ($deviceDetails.Count -eq 0) {
            return "No iOS devices found in Intune for email: $emailAddress"
        } else {
            return $deviceDetails
        }
    } catch {
        return "Failed to get iOS device details: $($_.Exception.Message)"
    }
}

# Function to revoke sign-in sessions for a user
function RevokeGraphSignInSessions {
    param (
        [Parameter(Mandatory = $true)]
        [string]$emailAddress
    )

    $accessToken = Get-IntuneAccessToken
    $headers = @{
        "Authorization" = "Bearer $accessToken"
        "Content-Type" = "application/json"
    }

    $uri = "https://graph.microsoft.com/v1.0/users/$emailAddress/revokeSignInSessions"

    try {
        $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers
        return $response.value
    } catch {
        $responseError = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($responseError)
        $responseBody = $reader.ReadToEnd() | ConvertFrom-Json
        $errorMessage = $responseBody.error.message
        Write-Warning "Failed to revoke sign-in sessions: $errorMessage"
    }
}

# Function to enable lost mode on a managed device
function Enable-LostMode {
    param (
        [Parameter(Mandatory = $true)]
        [string]$managedDeviceId,
        [string]$issueKey  # Added parameter for Jira issue key
    )

    $accessToken = Get-IntuneAccessToken
    $headers = @{
        "Authorization" = "Bearer $accessToken"
        "Content-Type" = "application/json"
    }

    $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$managedDeviceId/enableLostMode"

    $body = @{
        "message" = "Please contact Help Desk - Refer to $issueKey"  # Custom message
        "phoneNumber" = ""  # phone number
    } | ConvertTo-Json

    try {
        $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body
        Write-Host "Lost mode enabled for device $managedDeviceId with message: 'Please contact Help Desk - Refer to $issueKey'"
        return $true
    } catch {
        if ($_.Exception -is [Microsoft.PowerShell.Commands.HttpResponseException]) {
            $errorResponse = $_.Exception.ErrorDetails.Message | ConvertFrom-Json
            $errorMessage = $errorResponse.error.message
            Write-Warning "Failed to enable lost mode: $errorMessage"
        } else {
            Write-Warning "Failed to enable lost mode: $($_.Exception.Message)"
        }
        return $false
    }
}



# Function to check and assign license
function CheckAndAssignLicense {
    param (
        [Parameter(Mandatory = $true)]
        [string]$emailAddress
    )

    $accessToken = Get-IntuneAccessToken
    if (-not $accessToken) {
        Write-Host "Failed to obtain access token."
        return
    }

    $headers = @{
        "Authorization" = "Bearer $accessToken"
        "Content-Type" = "application/json"
    }

    $F3SkuId = $config.F3SkuId
    $E3SkuId = $config.E3SkuId

    $uriGetLicenses = "https://graph.microsoft.com/v1.0/users/$emailAddress/licenseDetails"
    try {
        $currentLicensesResponse = Invoke-RestMethod -Method Get -Uri $uriGetLicenses -Headers $headers
        $currentLicenses = $currentLicensesResponse.value
        
        $hasF3 = $currentLicenses.skuId -contains $F3SkuId
        $hasE3 = $currentLicenses.skuId -contains $E3SkuId

        if ($hasF3 -and -not $hasE3) {
            $body = @{
                "addLicenses" = @(@{ "skuId" = $E3SkuId })
                "removeLicenses" = @($F3SkuId)
            } | ConvertTo-Json

            $uriAssignLicense = "https://graph.microsoft.com/v1.0/users/$emailAddress/assignLicense"

            Invoke-RestMethod -Method Post -Uri $uriAssignLicense -Headers $headers -Body $body
            Write-Host "Successfully switched from F3 to E3."
            
            $Global:LicenseChanged = $true
            # Wait with progress display
            $duration = 360 # 6 minutes
            $startTime = Get-Date
            for ($i = 0; $i -le $duration; $i++) {
                $percentComplete = ($i / $duration) * 100
                $elapsedTime = (Get-Date) - $startTime
                $statusMessage = "Elapsed time: $($elapsedTime.ToString("hh\:mm\:ss"))"
                Write-Progress -Activity "Waiting..." -Status $statusMessage -PercentComplete $percentComplete -SecondsRemaining ($duration - $i)
                Start-Sleep -Seconds 1
            }
            Write-Progress -Activity "Waiting..." -Completed
            Write-Host "Done waiting."

        } elseif ($hasE3) {
            Write-Host "$emailAddress already has an E3 license."
        } else {
            Write-Host "$emailAddress does not have an F3 license or already has an E3 license. No action required."
        }

    } catch {
        $errorResponse = $_.ErrorDetails.Message
        if ($errorResponse -match "does not have any available licenses") {
            return "No available E3 licenses to assign."
        } else {
            Write-Warning "Failed to check or switch licenses for $emailAddress. Error: $errorResponse"
        }
    }

    CheckLitigationHoldStatus -emailAddress $emailAddress
}



# Function to connect to Exchange Online
function ConnectToExchangeOnline {
    try {
        Connect-ExchangeOnline -CertificateThumbprint $config.certThumbprint -AppId $config.clientId -Organization $config.organization -ShowBanner:$false
    } catch {
        Write-Host "Failed to connect to Exchange Online. Error: $($_.Exception.Message)"
        throw "Failed to connect to Exchange Online."
    }
}

# Function to disconnect from Exchange Online
function DisconnectFromExchangeOnline {
    try {
        Disconnect-ExchangeOnline -Confirm:$false
    } catch {
        Write-Host "Failed to disconnect from Exchange Online. Error: $($_.Exception.Message)"
    }
}

# Function to check litigation hold status
function CheckLitigationHoldStatus {
    param (
        [Parameter(Mandatory = $true)]
        [string]$emailAddress
    )
    
    ConnectToExchangeOnline
    
    try {
        $mailbox = Get-Mailbox -Identity $emailAddress -ErrorAction Stop
        Write-Host "Checking litigation hold status."
    
        if (-not $mailbox.LitigationHoldEnabled) {
            Write-Host "Litigation hold is not enabled."
            return $false
        } else {
            Write-Host "Litigation hold is already enabled."
            return $true
        }
    } catch {
        Write-Host "Failed to check litigation hold status. Error: $($_.Exception.Message)"
        return $null
    } finally {
        DisconnectFromExchangeOnline
    }
}

# Function to enable litigation hold
function EnableLitigationHold {
    param (
        [Parameter(Mandatory = $true)]
        [string]$emailAddress,
        [string]$IssueKey,
        [switch]$Quiet
    )

    ConnectToExchangeOnline
    
    try {
        if (-not $Quiet) {
            Write-Host "Enabling litigation hold for $emailAddress."
        }

        $retentionComment = "Lit hold for separation purposes. Related to Jira issue $IssueKey."
        $retentionUrl = "Your_Jira_URL/browse/$IssueKey"

        Set-Mailbox -Identity $emailAddress -LitigationHoldEnabled $true -RetentionComment $retentionComment -RetentionUrl $retentionUrl

        if (-not $Quiet) {
            Write-Host "Litigation hold successfully enabled for $emailAddress."
        }
        return $true
    } catch {
        if (-not $Quiet) {
            Write-Host "Failed to enable litigation hold for $emailAddress. Error: $($_.Exception.Message)"
        }
        return $false
    } finally {
        DisconnectFromExchangeOnline
    }
}



# Function to revert license after litigation hold
function RevertLicenseAfterLitigationHold {
    param (
        [Parameter(Mandatory = $true)]
        [string]$emailAddress
    )

    if ($Global:LicenseChanged -eq $true) {
        $accessToken = Get-IntuneAccessToken
        if (-not $accessToken) {
            Write-Host "Failed to obtain access token."
            return
        }

        $headers = @{
            "Authorization" = "Bearer $accessToken"
            "Content-Type" = "application/json"
        }

        Write-Host "Waiting to ensure all previous changes have propagated..."
        $duration = 360 # Adjust as needed for propagation time
        $startTime = Get-Date

        for ($i = 0; $i -le $duration; $i++) {
            $percentComplete = ($i / $duration) * 100
            $elapsedTime = (Get-Date) - $startTime
            $statusMessage = "Elapsed time: $($elapsedTime.ToString("hh\:mm\:ss"))"
            Write-Progress -Activity "Waiting for propagation..." -Status $statusMessage -PercentComplete $percentComplete -SecondsRemaining ($duration - $i)
            Start-Sleep -Seconds 1
        }
        Write-Progress -Activity "Waiting for propagation..." -Completed

        $uriAssignLicense = "https://graph.microsoft.com/v1.0/users/$emailAddress/assignLicense"
        $body = @{
            "addLicenses" = @( @{ "skuId" = $config.F3SkuId } ) # F3 SKU ID from config
            "removeLicenses" = @( $config.E3SkuId ) # E3 SKU ID from config
        } | ConvertTo-Json

        try {
            $response = Invoke-RestMethod -Method Post -Uri $uriAssignLicense -Headers $headers -Body $body
            Write-Host "License successfully reverted from E3 to F3."
        } catch {
            $errorMessage = $_.Exception.Message
            Write-Warning "Failed to revert license. Error: $errorMessage"
        }
    } else {
        Write-Host "No license change detected, skipping reversion."
    }
}

function BlockUserSignIn {
    param (
        [Parameter(Mandatory = $true)]
        [string]$emailAddress
    )

    $accessToken = Get-IntuneAccessToken
    if (-not $accessToken) {
        return $false
    }

    $headers = @{
        "Authorization" = "Bearer $accessToken"
        "Content-Type" = "application/json"
    }

    $uri = "https://graph.microsoft.com/v1.0/users/$emailAddress"

    $body = @{
        accountEnabled = $false
    } | ConvertTo-Json

    try {
        Invoke-RestMethod -Uri $uri -Headers $headers -Method PATCH -Body $body
        return $true
    }
    catch {
        return $false
    }
}



#Removes Office License
function RemoveLicense {
    param (
        [Parameter(Mandatory = $true)]
        [string]$emailAddress
    )

    $accessToken = Get-IntuneAccessToken
    if (-not $accessToken) {
        Write-Host "Failed to obtain access token."
        return
    }

    $headers = @{
        "Authorization" = "Bearer $accessToken"
        "Content-Type" = "application/json"
    }

    
    $F3SkuId = $config.F3SkuId
    $E3SkuId = $config.E3SkuId

    $uriGetLicenses = "https://graph.microsoft.com/v1.0/users/$emailAddress/licenseDetails"
    try {
        $currentLicensesResponse = Invoke-RestMethod -Method Get -Uri $uriGetLicenses -Headers $headers
        $currentLicenses = $currentLicensesResponse.value
        
        $hasF3 = $currentLicenses.skuId -contains $F3SkuId
        $hasE3 = $currentLicenses.skuId -contains $E3SkuId

        # Determine which license to remove based on what the user has.
        if ($hasF3) {
            $licenseToRemove = $F3SkuId
        } elseif ($hasE3) {
            $licenseToRemove = $E3SkuId
        }

        if ($licenseToRemove) {
            $body = @{
                "addLicenses" = @()
                "removeLicenses" = @($licenseToRemove)
            } | ConvertTo-Json

            $uriAssignLicense = "https://graph.microsoft.com/v1.0/users/$emailAddress/assignLicense"
            Invoke-RestMethod -Method Post -Uri $uriAssignLicense -Headers $headers -Body $body
            Write-Host "License $licenseToRemove removed"
        } else {
            Write-Host "User does not have F3 or E3 license to remove."
        }
    } catch {
        Write-Error "Error retrieving or removing license for $emailAddress $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function 'Get-IntuneAccessToken', 'Get-IntuneDeviceDetails', 'RevokeGraphSignInSessions', 'Enable-LostMode', 'CheckLitigationHoldStatus', 'EnableLitigationHold', 'CheckAndAssignLicense','RevertLicenseAfterLitigationHold', 'RemoveLicense', 'BlockUserSignIn'

