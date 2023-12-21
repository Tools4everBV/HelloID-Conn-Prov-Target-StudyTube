#####################################################
# HelloID-Conn-Prov-Target-StudyTubeV2-Delete
#
# Version: 1.1.0
#####################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $AccountReference | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

#region functions
function Resolve-HTTPError {
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
    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true) {
        $auditLogs.Add([PSCustomObject]@{
                Message = "Delete StudyTubeV2 account from: [$($p.DisplayName)] will be executed during enforcement"
            })
    }

    if (-not($dryRun -eq $true)) {
        Write-Verbose 'Retrieving authorization token'
        $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
        $headers.Add("Content-Type", "application/x-www-form-urlencoded")
        $tokenBody = @{
            client_id     = $($config.ClientId)
            client_secret = $($config.ClientSecret)
            grant_type    = 'client_credentials'
            scope         = 'read write'
        }
        $tokenResponse = Invoke-RestMethod -Uri "$($config.TokenUrl)/gateway/oauth/token" -Method 'POST' -Headers $headers -Body $tokenBody -verbose:$false

        Write-Verbose 'Setting authorization header'
        $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
        $headers.Add("Authorization", "Bearer $($tokenResponse.access_token)")

        Write-Verbose "Deleting StudyTubeV2 account with accountReference: [$aRef]"
        $splatUpdateUserParams = @{
            Uri     = "$($config.BaseUrl)/api/v2/users/$aRef"
            Method  = 'DELETE'
            Headers = $headers
        }
        $null = Invoke-RestMethod @splatUpdateUserParams -StatusCodeVariable statusCode -verbose:$false
        if ($statusCode -eq 204) {
            $success = $true
            $auditLogs.Add([PSCustomObject]@{
                    Action  = "DeleteAccount"
                    Message = 'Delete account was successful'
                    IsError = $false
                })
        }
    }
}
catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-HTTPError -ErrorObject $ex
        $errorMessage = "Could not delete StudyTubeV2 account. Error: $($errorObj.ErrorMessage)"
    }
    else {
        $errorMessage = "Could not delete StudyTubeV2 account. Error: $($ex.Exception.Message)"
    }
    Write-Verbose $errorMessage
    $auditLogs.Add([PSCustomObject]@{
            Action  = "DeleteAccount"
            Message = $errorMessage
            IsError = $true
        })
}
finally {
    $result = [PSCustomObject]@{
        Success   = $success
        Auditlogs = $auditLogs
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}