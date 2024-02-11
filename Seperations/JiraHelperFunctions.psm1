##Jira Helper Functions



# Function to update the summary with "Effective Date" if it's not already present
function Update-SummaryWithDate {
    param (
        [string]$issueKey,
        [string]$summary,
        [string]$effectiveDate
    )

    $effectiveDatePattern = "Effective Date: (\d{2}/\d{2}/\d{4})" # Pattern to match the date format MM/dd/yyyy

    # Check if the summary already contains an effective date
    if ($summary -match $effectiveDatePattern) {
        $currentEffectiveDate = $matches[1]
        # Update the summary only if the effective date has changed
        if ($currentEffectiveDate -ne $effectiveDate) {
            $summary = $summary -replace $effectiveDatePattern, "Effective Date: $effectiveDate"
            Update-IssueSummary -issueKey $issueKey -summary $summary
        }
    } else {
        # If no effective date in the summary, add it
        $summary += " Effective Date: $effectiveDate"
        Update-IssueSummary -issueKey $issueKey -summary $summary
    }

    return $summary
}

function Update-IssueSummary {
    param (
        [string]$issueKey,
        [string]$summary
    )

    $updateIssueUrl = "$global:JiraApiBaseUrl/issue/$issueKey"
    $updateIssueBody = @{
        "fields" = @{
            "summary" = $summary
        }
    } | ConvertTo-Json -Depth 10

    try {
        Invoke-RestMethod -Uri $updateIssueUrl -Method Put -Headers $headers -Body $updateIssueBody
        Write-Host "Summary updated for issue $issueKey"
    } catch {
        Write-Host ("Error updating summary for issue {0}: {1}" -f $issueKey, $_.Exception.Message)
    }
}


# Function to extract Employee Name, Job Title, Location, and Effective Date from Jira issue description
function Get-IssueDetails {
    param ([Parameter(Mandatory = $true)] $issue)

    $details = @{}
    if ($issue -and $issue.fields.description) {
        foreach ($content in $issue.fields.description.content) {
            if ($content.type -eq "paragraph") {
                foreach ($item in $content.content) {
                    if ($item.type -eq "text" -and $item.text -match "(Employee Name|Job Title|Location|Effective Date|Department):\s*([^\r\n]+)") {
                        if ($matches[1] -eq "Department") {
                            # Only capture the first two words of the Department
                            $departmentWords = $matches[2].Trim() -split '\s+'
                            if ($departmentWords.Count -gt 1) {
                                $details[$matches[1]] = "$($departmentWords[0]) $($departmentWords[1])"
                            } else {
                                $details[$matches[1]] = $matches[2].Trim()
                            }
                        } else {
                            $details[$matches[1]] = $matches[2].Trim()
                        }
                    }
                }
            }
        }
    }

    return $details
}



# Function to add a comment to a Jira issue only if it doesn't already exist
function Send-JiraComment {
    param (
        [Parameter(Mandatory = $true)]
        [string]$issueKey,
        [string]$commentContent
    )

    $commentsUrl = "$global:JiraApiBaseUrl/issue/$issueKey/comment"
    $existingComments = Invoke-RestMethod -Uri $commentsUrl -Method Get -Headers $headers
    $commentExists = $false

    foreach ($existingComment in $existingComments.comments) {
        if ($existingComment.body -ne $null -and $existingComment.body.type -eq "doc") {
            $existingContent = $existingComment.body.content | ForEach-Object { $_.content | ForEach-Object { $_.text } }
            $existingContent = $existingContent -join ""

            $normalizedExistingContent = $existingContent -replace "’", "'"
            $normalizedNewComment = $commentContent -replace "’", "'"

            if ($normalizedExistingContent -eq $normalizedNewComment) {
                Write-Host "Comment already exists on issue $issueKey. Skipping."
                $commentExists = $true
                break
            }
        }
    }

    if (-not $commentExists) {
        $commentBody = @{
            "body" = @{
                "type" = "doc"
                "version" = 1
                "content" = @(
                    @{
                        "type" = "paragraph"
                        "content" = @(
                            @{
                                "text" = $commentContent
                                "type" = "text"
                            }
                        )
                    }
                )
            }
        } | ConvertTo-Json -Depth 10

        $commentUrl = "$global:JiraApiBaseUrl/issue/$issueKey/comment"

        try {
            Invoke-RestMethod -Uri $commentUrl -Method Post -Headers $headers -Body $commentBody
            Write-Host "Comment added to issue $issueKey"
        } catch {
            Write-Host ("Error adding comment to issue {0}: {1}" -f $issueKey, $_.Exception.Message)
        }
    }
}

#Update the status of a Jira issue
function Update-JiraIssueStatus {
    param (
        [Parameter(Mandatory = $true)]
        [string]$issueKey,
        [string]$targetStatusName = "Done" # Add Status type to transition ticket to
    )

    # First, get available transitions for the issue
    $transitionsUrl = "$global:JiraApiBaseUrl/issue/$issueKey/transitions"
    try {
        $transitionsResponse = Invoke-RestMethod -Uri $transitionsUrl -Method Get -Headers $headers
        $transitionId = ($transitionsResponse.transitions | Where-Object { $_.name -eq $targetStatusName }).id

        if (-not $transitionId) {
            Write-Host "No transition to '$targetStatusName' found for issue $issueKey"
            return
        }

        # Then, perform the transition
        $updateIssueBody = @{
            "transition" = @{
                "id" = $transitionId
            }
        } | ConvertTo-Json -Depth 10

        Invoke-RestMethod -Uri $transitionsUrl -Method Post -Headers $headers -Body $updateIssueBody
        Write-Host "Status updated for issue $issueKey to '$targetStatusName'"
    } catch {
        Write-Host ("Error updating status to '$targetStatusName' for issue {0}: {1}" -f $issueKey, $_.Exception.Message)
    }
}

function AssignJiraIssueToUser {
    param (
        [Parameter(Mandatory = $true)]
        [string]$issueKey
    )

    $assigneeAccountId = $global:config.assigneeAccountId
    $assigneeUrl = "$global:JiraApiBaseUrl/issue/$issueKey/assignee"

    try {
        $assigneeBody = @{
            "accountId" = $assigneeAccountId
        }

        $jsonBody = $assigneeBody | ConvertTo-Json -Depth 10

        Invoke-RestMethod -Uri $assigneeUrl -Method Put -Headers $headers -Body $jsonBody
        Write-Host "Issue $issueKey assigned to user with account ID $assigneeAccountId"
    } catch {
        $responseError = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($responseError)
        $responseBody = $reader.ReadToEnd()
        Write-Host ("Error assigning issue {0} to user with account ID {1}: {2} - Details: {3}" -f $issueKey, $assigneeAccountId, $_.Exception.Message, $responseBody)
    }
}

function UpdateJiraIssueCustomFields {
    param (
        [Parameter(Mandatory = $true)]
        [string]$issueKey,
        [string]$employeeName,
        [string]$location,
        [string]$department
    )

    $headers = @{
        "Authorization" = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($global:JiraUsername):$($global:JiraApiToken)"))
        "Content-Type" = "application/json"
    }

    # First, get the current issue details to check existing values
    $issueDetailsUrl = "$global:JiraApiBaseUrl/issue/$issueKey"
    $currentIssueDetails = Invoke-RestMethod -Uri $issueDetailsUrl -Method Get -Headers $headers
    $currentEmployeeName = $currentIssueDetails.fields.customfield_10163
    $currentLocation = $currentIssueDetails.fields.customfield_10054.value
    $currentDepartment = $currentIssueDetails.fields.customfield_10055.value

    $body = @{ "fields" = @{} }

    if ($currentEmployeeName -ne $employeeName) {
        $body.fields.customfield_10163 = $employeeName
    }
    if ($currentLocation -ne $location) {
        $body.fields.customfield_10054 = @{ "value" = $location }
    }
    if ($currentDepartment -ne $department) {
        $body.fields.customfield_10055 = @{ "value" = $department }
    }

    # Check if there are fields to update
    if ($body.fields.Count -gt 0) {
        $bodyJson = $body | ConvertTo-Json -Depth 10
        try {
            $response = Invoke-RestMethod -Uri $issueDetailsUrl -Method Put -Headers $headers -Body $bodyJson
            Write-Host "Custom fields updated successfully for issue $issueKey."
        } catch {
            Write-Host "Failed to update custom fields for issue $issueKey $($_.Exception.Message)"
        }
    } else {
        Write-Host "No custom fields updates required for issue $issueKey."
    }
}


Export-ModuleMember -Function Update-SummaryWithDate, Get-IssueDetails, Send-JiraComment, Update-JiraIssueStatus, AssignJiraIssueToUser, UpdateJiraIssueCustomFields
