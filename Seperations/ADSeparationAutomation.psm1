# JiraAPI Module
Import-Module 'C:\Scripts\Seperations\JiraHelperFunctions.psm1' -Force
Import-Module 'C:\Scripts\Seperations\MicrosoftGraphAPI.psm1' -Force
Import-Module 'C:\Scripts\Seperations\ActiveDirectoryUtils.psm1' -Force

# Global Variables
$global:JiraApiBaseUrl = "Your_Jira_URL/rest/api/3"

function Invoke-IssueProcessing {
    $jqlCriteria = "project='$projectKey' AND issuetype = 'Service Request' AND status = 'AD/Exchange' AND 'Request Type' = 'Separation  (AD)' AND resolution = 'Unresolved'"
    $issueList = @()

    do {
        $url = "$global:JiraApiBaseUrl/search?jql=$jqlCriteria&startAt=$startAt&maxResults=$maxResults"
        $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers

        foreach ($issue in $response.issues) {
            if ($issue) {
                $details = Get-IssueDetails -issue $issue
                $employeeName = $details["Employee Name"]
                $location = $details["Location"] 
                $department = $details["Department"] 
                $effectiveDate = $details["Effective Date"]
                $disableCommentAdded = $false
                
                # Fetch AD employee details
                $adEmployeeDetails = GetADEmployeeDetails -employeeName $employeeName

                if (-not $adEmployeeDetails.Email) {
                    # If no AD user found, make a general comment and skip to status update and assignment
                    $commentContent = "No Active Directory user found for $employeeName."
                    Send-JiraComment -issueKey $issue.key -commentContent $commentContent
                    
                    # Update issue status and assign it
                    Update-JiraIssueStatusToFLConnect -issueKey $issue.key
                    AssignJiraIssueToUser -issueKey $issue.key
                    
                    Write-Host "No AD user found for $employeeName, issue $issue.key updated and assigned."
                    continue
                }

                $intuneDeviceDetails = if ($adEmployeeDetails.Email) {
                    $deviceDetails = Get-IntuneDeviceDetails -emailAddress $adEmployeeDetails.Email
                    
                    if ($deviceDetails -is [string]) {
                        # If a string is returned, it means no devices were found or there was an error.
                        $deviceDetails
                    } elseif ($deviceDetails -is [array] -and $deviceDetails.Count -gt 0) {
                        # If an array is returned, process it to create a descriptive string.
                        $info = $deviceDetails | ForEach-Object {
                            "Device Name: $($_.DeviceName), Serial Number: $($_.SerialNumber)"
                        }
                        # Join all device information lines into a single string to return.
                        $info -join "`r`n"
                    } else {
                        "No iOS devices found in Intune for email: $adEmployeeDetails.Email"
                    }
                } else {
                    "No Mobile Device found for $employeeName"
                }
                
                $computerInfo = FindComputerByEmployeeName -employeeName $employeeName
                
     # Update Custom fields: Employee Name, Department, Location
     UpdateJiraIssueCustomFields -issueKey $issue.key -employeeName $employeeName -location $location -department $department

# Check litigation hold status
$litigationHoldStatus = CheckLitigationHoldStatus -emailAddress $adEmployeeDetails.Email
# Initially, assume the license is not adjusted
$licenseAdjusted = $false
# Check the litigation hold status first
if (-not $litigationHoldStatus) {
    # Check and possibly adjust the license, assuming this function returns a result or status
    $licenseAdjustmentResult = CheckAndAssignLicense -emailAddress $adEmployeeDetails.Email
    
    # Determine if an E3 license is assigned and act based on that
    if ($licenseAdjustmentResult -ne "No available E3 licenses to assign.") {
        # Assume that not receiving the specific "no E3 licenses" message means we can proceed
        $licenseAdjusted = $true
        $enableLitigationHoldResult = EnableLitigationHold -emailAddress $adEmployeeDetails.Email -IssueKey $issue.key -Quiet
        $litigationHoldComment = "Litigation Hold: Enabled based on E3 license assignment"
    } else {
        # Here, we directly address the "no E3 licenses available" scenario
        $enableLitigationHoldResult = $false
        $litigationHoldComment = "Litigation Hold: Not enabled - No available E3 licenses to assign."
    }
} elseif ($litigationHoldStatus) {
    # If litigation hold is already set, we log that status
    $litigationHoldComment = "Litigation Hold: Already enabled"
} else {
    # Catch-all for any other unexpected scenarios
    $enableLitigationHoldResult = $false
    $litigationHoldComment = "Litigation Hold: Not enabled - Unexpected condition."
}
# General Comment Collecting Details
$generalComment = @"
AD Status: $($adEmployeeDetails.Status)
Email: $($adEmployeeDetails.Email)
Mobile Number: $($adEmployeeDetails.Mobile)
$intuneDeviceDetails
$computerInfo
$litigationHoldComment
"@
# Determine if a new comment about litigation hold needs to be posted
if ($litigationHoldUpdated) {
    # If there's an update, post only the litigation hold comment
    Send-JiraComment -issueKey $issue.key -commentContent "$($newLitigationHoldComment)"
} else {
    # If no update, post the general comment with litigation hold status appended
    Send-JiraComment -issueKey $issue.key -commentContent "$($generalComment)`n$($newLitigationHoldComment)"
}
                # AD Groups Comment
                $adGroups = GetADEmployeeGroups -employeeName $employeeName
                $adGroupsComment = "AD Groups: $adGroups"
                Send-JiraComment -issueKey $issue.key -commentContent $adGroupsComment



  # Revert license after litigation hold (if needed)
  if (-not $litigationHoldStatus -and $licenseAdjusted) {
    $RevertLicenseAfterLitigationHold = RevertLicenseAfterLitigationHold -emailAddress $adEmployeeDetails.Email
}

        
                # Actions based on effective date or immediate action if already disabled
                $effectiveDateTime = Get-EffectiveDateTime -effectiveDate $effectiveDate -offsetHours $config.effectiveDateTimeOffsetHours
                
                if ($adEmployeeDetails.Status -eq "disabled" -or ($effectiveDateTime -and (Get-Date) -ge $effectiveDateTime)) {
                    $actionNote = if ($adEmployeeDetails.Status -eq "disabled") { "Employee account already disabled. Processing Separation." } else { "Processing actions based on effective date for employee: $employeeName" }
                    Write-Host $actionNote
                    try {
                        # Immediate actions for disabled account or actions based on effective date
                        $disableResult = DisableAdAccountOnEffectiveDate -employeeName $employeeName
                        $computerDisableResult = DisableComputer -employeeName $employeeName
                        $signInSessionRevokeResult = RevokeGraphSignInSessions -emailAddress $adEmployeeDetails.Email
                        $lostModeResult = Enable-LostMode -managedDeviceId $firstDeviceId -issueKey $issue.key
                        $BlockSigninResult = BlockUserSignIn -emailAddress $adEmployeeDetails.Email

                        # Combine comments regarding account actions
                        $combinedComment = "$($disableResult.Result) - $($disableResult.Message)`r`nComputer actions: $computerDisableResult`r`nSign-in sessions revoked: $signInSessionRevokeResult`r`nLost mode enabled: $lostModeResult`r`nBlocked Sign: $BlockSigninResult"
                        Send-JiraComment -issueKey $issue.key -commentContent $combinedComment
                        $disableCommentAdded = $true
                    } catch {
                        Write-Host "Error occurred in processing actions: $_"
                    }
                }
                
                # Check if combined comment was added successfully
                if ($disableCommentAdded -eq $true) {
                    # Update issue status and assign it
                    try {
                        Update-JiraIssueStatus -issueKey $issue.key
                        AssignJiraIssueToUser -issueKey $issue.key
                        RemoveLicense -emailAddress $adEmployeeDetails.Email
                        MoveADUserToDisabledOU -employeeName $employeeName
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
