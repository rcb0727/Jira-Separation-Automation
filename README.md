# Jira-Seperation_Automation
This script utilizes Jira API, MSGraph API, and Active Directory Module to Separate an employee 

To make MS-Graph work, create an App registration and add these permissions. All permissions should be application permissions
![image](https://github.com/rcb0727/Jira-Seperation-Automation/assets/130812613/cf6385dc-3130-4cc1-b97a-29321e6f9384)

Update Config File with your information
![image](https://github.com/rcb0727/Jira-Seperation-Automation/assets/130812613/4cf02870-6c04-42f3-85a7-d33eb5b67986)

Update Function Update-JiraIssueStatus, add the status name to transition to
![image](https://github.com/rcb0727/Jira-Seperation-Automation/assets/130812613/3c652022-d49e-415d-bbfa-a423fe7c3f45)

Update Jira URL in ADSpeparationAutomation

![image](https://github.com/rcb0727/Jira-Seperation-Automation/assets/130812613/d821f50a-d4ee-4083-aee8-707afeaba4ab)


[!["Buy Me A Coffee"](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://www.buymeacoffee.com/rcb0727)

**What the script does:**

Checks if Jira Ticket Status is in ‘AD/Exchange’

Checks if Request Type is set to ‘Separation’

Updates Summary of Jira ticket with Effective Date

Adds Employee Name in Custom Field Employee Name , Adds Department in Custom Field Department , Adds Location to Custom Field Location

Finds user in AD by searching for Surname, Given name, Display name against field Employee Name. It also ensures Location and Title on Jira ticket matches AD user

Checks if users email is on Litigation hold/ Checks for F3 and E3 License

If Litigation hold is off and user has an F3 License, script switches license to E3 and enables Litigation hold. Then reverts license back to F3

If Litigation hold is off and user has E3 license, skips license swap and enables Litigation hold

If litigation hold is on, skips function

Comments user account information/Computer used if Applicable, and AD Groups

If comments and Litigation hold is completed, items are skipped when script is ran again

On Effective Date of Separation

Script checks that the effective date on the Jira ticket against the server time and date. If time and date have not been met, second part of the script will not run.

At 4pm on effective date script does the following:

Disables AD account, removes AD groups, removes manager, hides from Address book

Disables Computer Object

Revokes all Azure active sessions

Puts mobile device in lost mode

Comments that all actions have been completed

Once all items are completed, ticket status is changed to next status and ticket is assign to next person

Removes License from Office 365 Portal

**Functions can be removed or added. Make sure to update Export-ModuleMember with new or removed functions. **

**Links used: **

JQL [JQL fields | Jira Service Management Cloud | Atlassian Support](https://support.atlassian.com/jira-service-management-cloud/docs/jql-fields/) 

Comment API calls [The Jira Cloud platform REST API (atlassian.com)](https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issue-comments/#api-group-issue-comments) 

Custom field options in Jira issue [The Jira Cloud platform REST API (atlassian.com)](https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issue-custom-field-options/#api-group-issue-custom-field-options) 

Issue API calls [The Jira Cloud platform REST API (atlassian.com)](https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issues/#api-group-issues) 

Placing Litigation hold on mailbox [Place a mailbox on Litigation Hold | Microsoft Learn](https://learn.microsoft.com/en-us/exchange/policy-and-compliance/holds/litigation-holds?view=exchserver-2019) 

enabling Lost Mode [enableLostMode action - Microsoft Graph beta | Microsoft Learn](https://learn.microsoft.com/en-us/graph/api/intune-devices-manageddevice-enablelostmode?view=graph-rest-beta) 

Assigning Office licenses [user: assignLicense - Microsoft Graph v1.0 | Microsoft Learn](https://learn.microsoft.com/en-us/graph/api/user-assignlicense?view=graph-rest-1.0&tabs=http)

Revoke user sessions in Azure [https://learn.microsoft.com/en-us/graph/api/user-revokesigninsessions?view=graph-rest-1.0&tabs=http](https://learn.microsoft.com/en-us/graph/api/user-revokesigninsessions?view=graph-rest-1.0&tabs=http)

Authenticating Powershell Exchange via Certificate[https://learn.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2?view=exchange-ps](https://learn.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2?view=exchange-ps) 

List of Office 365 sku's to be able to assign licenses[https://gist.github.com/mczerniawski/950e5c102c704d628ce38522ef4ad0f9](https://gist.github.com/mczerniawski/950e5c102c704d628ce38522ef4ad0f9)

[!["Buy Me A Coffee"](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://www.buymeacoffee.com/rcb0727)
