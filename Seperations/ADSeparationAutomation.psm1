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

        f        foreach ($issue in $response.issues) {
            if ($issue) {
                $details = Get-IssueDetails -issue $issue
                $employeeName = $details["Employee Name"]
                $location = $details["Location"] 
                $department = $details["Department"] 
                $effectiveDate = $details["Effective Date"]
                $summary = $issue.fields.summary
                $disableCommentAdded = $false

                # Update issue summary with effective date
                $updatedSummary = Update-SummaryWithDate -issueKey $issue.key -summary $summary -effectiveDate $effectiveDate
                
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
                    $deviceDetailsArray = @($deviceDetails)
                    if ($deviceDetailsArray.Count -gt 0) {
                        $formattedDetails = $deviceDetailsArray | ForEach-Object {
                            "Device Name: $($_.DeviceName), Serial Number: $($_.SerialNumber)"
                        }
                        $formattedDetails -join "`n"
                    } else {
                        "No iOS devices found in Intune for email: $($adEmployeeDetails.Email)"
                    }
                } else {
                    "No Mobile Device found for $employeeName"
                }
                
                $computerInfo = FindComputerByEmployeeName -employeeName $employeeName
                
     # Update Custom fields: Employee Name, Department, Location
     UpdateJiraIssueCustomFields -issueKey $issue.key -employeeName $employeeName -location $location -department $department

                $litigationHoldStatus = CheckLitigationHoldStatus -emailAddress $adEmployeeDetails.Email
                $licenseAdjusted = $false
                if (-not $litigationHoldStatus) {
                    $licenseAdjustmentResult = CheckAndAssignLicense -emailAddress $adEmployeeDetails.Email
                    if ($licenseAdjustmentResult -ne "No available E3 licenses to assign.") {
                        $licenseAdjusted = $true
                        EnableLitigationHold -emailAddress $adEmployeeDetails.Email -IssueKey $issue.key -Quiet
                        Send-JiraComment -issueKey $issue.key -commentContent "Litigation Hold: Enabled"
                    } else {
                        Send-JiraComment -issueKey $issue.key -commentContent "Litigation Hold: Not enabled - No available E3 licenses to assign."
                    }
                } elseif ($litigationHoldStatus) {
                    Send-JiraComment -issueKey $issue.key -commentContent "Litigation Hold: Already enabled"
                }

                $generalComment = @"
AD Status: $($adEmployeeDetails.Status)
Email: $($adEmployeeDetails.Email)
Mobile Number: $($adEmployeeDetails.Mobile)
$intuneDeviceDetails
$computerInfo
"@
                Send-JiraComment -issueKey $issue.key -commentContent $generalComment

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
                        $lostModeResult = Enable-LostMode -managedDeviceId $deviceDetails.ManagedDeviceId -issueKey
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
