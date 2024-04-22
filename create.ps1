#################################################
# HelloID-Conn-Prov-Target-StudyTube-Create
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Resolve-StudyTubeError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = ''
        }
        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $httpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $httpErrorObj.ErrorMessage = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
        }
        Write-Output $httpErrorObj
    }
}
#endregion

try {
    # Initial Assignments
    $outputContext.AccountReference = 'Currently not available'

    # Validate correlation configuration
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.personField
        $correlationValue = $actionContext.CorrelationConfiguration.personFieldValue

        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw 'Correlation is enabled but [personFieldValue] is empty. Please make sure it is correctly mapped'
        }

        Write-Information 'Retrieving authorization token'
        $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
        $headers.Add("Content-Type", "application/x-www-form-urlencoded")
        $tokenBody = @{
            client_id     = $($actionContext.Configuration.ClientId)
            client_secret = $($actionContext.Configuration.ClientSecret)
            grant_type    = 'client_credentials'
            scope         = 'read write'
        }
        $tokenResponse = Invoke-RestMethod -Uri "$($actionContext.Configuration.TokenUrl)/gateway/oauth/token" -Method 'POST' -Headers $headers -Body $tokenBody -verbose:$false

        Write-Information 'Setting authorization header'
        $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
        $headers.Add("Authorization", "Bearer $($tokenResponse.access_token)")

        Write-Information 'Retrieving total pages for the user resource'
        $splatResourceTotalParams = @{
            Uri     = "$($actionContext.Configuration.BaseUrl)/api/v2/users?perPage=$($actionContext.Configuration.PageSize)"
            Method  = 'HEAD'
            Headers = $headers
        }
        $null = Invoke-RestMethod @splatResourceTotalParams -ResponseHeadersVariable responseHeaders -verbose:$false

        Write-Information 'Retrieving all users from StudyTube'
        $page = 0
        $totalPages = $responseHeaders.'X-Total-Pages'[0] -as [int]
        $userList = [System.Collections.Generic.List[Object]]::new()
        do {
            $splatGetUserParams = @{
                Uri         = "$($actionContext.Configuration.BaseUrl)/api/v2/users?page=$page&perPage=$($actionContext.Configuration.PageSize)"
                Method      = 'GET'
                Headers     = $headers
            }
            $userResult = Invoke-RestMethod @splatGetUserParams
            $userList.AddRange($userResult)
            $page++
        } until ($page -eq $totalPages)

        # In some cases studytube returns the same userid multiple times (exactly the same record).
        $userListSorted = $userList | Sort-Object id -Unique

        $lookupUser = $userListSorted | Group-Object -Property uuid -AsHashTable -AsString
        $correlatedAccount = $lookupUser[$($correlationValue)]
        if (($correlatedAccount | measure-object).Count -gt 1) {
            throw "Found multiple user accounts [$($correlatedAccount.email -join ", ")] [$($correlatedAccount.id -join ", ")]"
        }
    }

    if ($null -ne $correlatedAccount) {
        $action = 'CorrelateAccount'
    } else {
        $action = 'CreateAccount'
    }

    # Add a message and the result of each of the validations showing what will happen during enforcement
    if ($actionContext.DryRun -eq $true) {
        Write-Information "[DryRun] $action StudyTube account for: [$($personContext.Person.DisplayName)], will be executed during enforcement"
    }

    # Process
    if (-not($actionContext.DryRun -eq $true)) {
        switch ($action) {
            'CreateAccount' {
                Write-Information 'Creating and correlating StudyTube account'
                $splatCreateUserParams = @{
                    Uri         = "$($actionContext.Configuration.BaseUrl)/api/v2/users"
                    Method      = 'POST'
                    Headers     = $headers
                    ContentType = 'application/x-www-form-urlencoded'
                    Body        = $actionContext.Data
                }
                $createdAccount = Invoke-RestMethod @splatCreateUserParams -verbose:$false
                $outputContext.Data = $createdAccount
                $outputContext.AccountReference = $createdAccount.id
                $auditLogMessage = "Create account was successful. AccountReference is: [$($outputContext.AccountReference)"
                break
            }

            'CorrelateAccount' {
                Write-Information 'Correlating StudyTube account'
                $outputContext.Data = $correlatedAccount
                $outputContext.AccountReference = $correlatedAccount.id
                $outputContext.AccountCorrelated = $true
                $auditLogMessage = "Correlated account: [$($correlatedAccount.id)] on field: [$($correlationField)] with value: [$($correlationValue)]"
                break
            }
        }

        $outputContext.success = $true
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Action  = $action
                Message = $auditLogMessage
                IsError = $false
            })
    }
} catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-StudyTubeError -ErrorObject $ex
        $auditMessage = "Could not create or correlate StudyTube account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not create or correlate StudyTube account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}
