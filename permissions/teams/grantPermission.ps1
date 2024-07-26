#####################################################
# HelloID-Conn-Prov-Target-StudyTube-GrantPermission
# PowerShell V2
#####################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Resolve-StudyTubeError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {
            $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json)
            $httpErrorObj.FriendlyMessage = $errorDetailsObject.error
            if ($errorDetailsObject.error_description) {
                $httpErrorObj.FriendlyMessage = $errorDetailsObject.error_description
            }
        } catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
        }
        Write-Output $httpErrorObj
    }
}
#endregion

# Begin
try {
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
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

    Write-Information "Verifying if a StudyTube account for [$($personContext.Person.DisplayName)] exists"
    try {
        $splatGetUserParams = @{
            Uri     = "$($actionContext.Configuration.BaseUrl)/api/v2/users/$($actionContext.References.Account)"
            Method  = 'GET'
            Headers = $headers
        }
        $correlatedAccount = Invoke-RestMethod @splatGetUserParams -verbose:$false
    } catch {
        throw
    }

    # Add a message and the result of each of the validations showing what will happen during enforcement
    if ($actionContext.DryRun -eq $true) {
        Write-Information "[DryRun] Grant StudyTube entitlement: [$($actionContext.References.Permission.Reference)], will be executed during enforcement"
    }

    # Process
    if (-not($actionContext.DryRun -eq $true)) {
        Write-Information "Granting StudyTubeV2 entitlement: [$($actionContext.References.Permission.Reference.DisplayName))] and ID: [$($actionContext.References.Permission.Reference)]"
        $splatGrantPermissionParams = @{
            Uri         = "$($actionContext.Configuration.BaseUrl)/api/v2/academy-teams/$($actionContext.References.Permission.Reference)/users"
            Method      = 'POST'
            Headers     = $headers
            ContentType = 'application/x-www-form-urlencoded'
            Body        = @{
                user_id = $actionContext.References.Account
            }
        }
        $null = Invoke-RestMethod @splatGrantPermissionParams -verbose:$false

        $outputContext.Success = $true
        $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = "Grant permission [$($actionContext.References.Permission.DisplayName)] was successful"
            IsError = $false
        })

    }
} catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-StudyTubeError -ErrorObject $ex
        $auditMessage = "Could not grant StudyTube permission. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not grant StudyTube permission. Error: $($_.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
        Message = $auditMessage
        IsError = $true
    })
}
