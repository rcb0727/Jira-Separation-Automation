# JiraAPI Module
Import-Module 'C:\Scripts\Seperations\JiraHelperFunctions.psm1' -Force
Import-Module 'C:\Scripts\Seperations\MicrosoftGraphAPI.psm1' -Force

# Global Variables
$global:JiraApiBaseUrl = "https://Your_Jira_URL.net/rest/api/3"

function Invoke-IssueProcessing {
    $jqlCriteria = "project='$projectKey' AND issuetype = 'Service Request' AND status = 'AD/Exchange' AND 'Request Type' = 'Separation  (AD)' AND resolution = 'Unresolved'" #Adjust Status and Request Type
    $issueList = @()

    do {
        $url = "$global:JiraApiBaseUrl/search?jql=$jqlCriteria&startAt=$startAt&maxResults=$maxResults"
        $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers

        foreach ($issue in $response.issues) {
            if ($issue) {
                $details = Get-IssueDetails -issue $issue
                $employeeName = $details["Employee Name"]
                $effectiveDate = $details["Effective Date"]
                $disableCommentAdded = $false
                
                # Fetch AD employee details
                $adEmployeeDetails = GetADEmployeeDetails -employeeName $employeeName
                $intuneDeviceDetails = if ($adEmployeeDetails.Email) { Get-IntuneDeviceDetails -emailAddress $adEmployeeDetails.Email } else { "No Mobile Device found for $employeeName" }
                $computerInfo = FindComputerByEmployeeName -employeeName $employeeName
                
                # Check litigation hold status
                $litigationHoldStatus = CheckLitigationHoldStatus -emailAddress $adEmployeeDetails.Email
                $licenseAdjusted = $false

                if (-not $litigationHoldStatus) {
                    # Check and assign licenses only if litigation hold is not enabled
                    $licenseAdjustmentResult = CheckAndAssignLicense -emailAddress $adEmployeeDetails.Email
                    $licenseAdjusted = $true

                    # Enable litigation hold after license assignment
                    EnableLitigationHold -emailAddress $adEmployeeDetails.Email
                }

                $enableLitigationHoldResult = EnableLitigationHold -emailAddress $adEmployeeDetails.Email -Quiet

# General Comment Collecting Details
                
$generalComment = @"
AD Status: $($adEmployeeDetails.Status)
Email: $($adEmployeeDetails.Email)
Mobile Number: $($adEmployeeDetails.Mobile)
$intuneDeviceDetails
$computerInfo
Litigation Hold: $enableLitigationHoldResult
"@
                Send-JiraComment -issueKey $issue.key -commentContent $generalComment

                # AD Groups Comment
                $adGroups = GetADEmployeeGroups -employeeName $employeeName
                $adGroupsComment = "AD Groups: $adGroups"
                Send-JiraComment -issueKey $issue.key -commentContent $adGroupsComment

                # Revert license after litigation hold (if needed)
                if (-not $litigationHoldStatus -and $licenseAdjusted) {
                    $RevertLicenseAfterLitigationHold = RevertLicenseAfterLitigationHold -emailAddress $adEmployeeDetails.Email
                }

                # Actions based on effective date
                $effectiveDateTime = Get-EffectiveDateTime -effectiveDate $effectiveDate -offsetHours $config.effectiveDateTimeOffsetHours
                
                if (-not $litigationHoldStatus -and $adEmployeeDetails.Status -eq "enabled" -and (Get-Date) -ge $effectiveDateTime) {
                    $disableResult = DisableAdAccountOnEffectiveDate -employeeName $employeeName -effectiveDate $effectiveDate
                    $computerDisableResult = DisableComputer -employeeName $employeeName
                    $signInSessionRevokeResult = RevokeGraphSignInSessions -emailAddress $adEmployeeDetails.Email
                    $lostModeResult = Enable-LostMode -managedDeviceId (Get-IntuneDeviceDetails -emailAddress $adEmployeeDetails.Email).split(',')[0] -issueKey $issue.key

                    # Combine comments regarding disabling account
                    $combinedComment = "$($disableResult.Result) - $($disableResult.Message)`r`nComputer actions: $computerDisableResult`r`nSign-in sessions revoked: $signInSessionRevokeResult`r`nLost mode enabled: $lostModeResult"
                    Send-JiraComment -issueKey $issue.key -commentContent $combinedComment
                    $disableCommentAdded = $true
                }
                
                # Check if combined comment was added successfully
                if ($disableCommentAdded -eq $true) {
                    # Update issue status and assign it
                    try {
                        Update-JiraIssueStatus -issueKey $issue.key
                        AssignJiraIssueToUser -issueKey $issue.key
                    } catch {
                        Write-Host "Failed to update status and assign issue $issue.key. Error: $($_.Exception.Message)"
                    }
                }

                Write-Host "--------------------------------------------------------------"
            }
        }

        $startAt += $maxResults
    } while ($startAt -lt $response.total)
}

Invoke-IssueProcessing

Export-ModuleMember -Function 'Invoke-IssueProcessing'
