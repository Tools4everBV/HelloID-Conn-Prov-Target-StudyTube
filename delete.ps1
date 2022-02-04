#####################################################
# HelloID-Conn-Prov-Target-StudyTube-Delete
#
# Version: 1.0.0
#####################################################
# Initialize default value's
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
        } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $httpErrorObj.ErrorMessage = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
        }
        Write-Output $httpErrorObj
    }
}
#endregion

try {
    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true){
        $auditLogs.Add([PSCustomObject]@{
            Message = "Delete StudyTube account from: [$($p.DisplayName)], will be executed during enforcement"
        })
    }

    if (-not($dryRun -eq $true)) {
        Write-Verbose "Deleting StudyTube account: [$aRef] from: [$($p.DisplayName)]"
        Write-Verbose 'Adding authorization headers'
        $authorization = "$($config.CompanyID):$($config.ApiToken)"
        $base64String = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($authorization))
        $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
        $headers.Add("Authorization", "Basic $($base64String)")

        $splatDeleteUserParams = @{
            Uri         = "$($config.BaseUrl)/v1/users/$aRef"
            Method      = 'DELETE'
            Headers     = $headers
            ContentType = 'application/json'
        }
        Invoke-RestMethod @splatDeleteUserParams -StatusCodeVariable statusCode
        if ($statusCode -eq 204){
            $success = $true
            $auditLogs.Add([PSCustomObject]@{
                Message = "Delete account for: [$($p.DisplayName)] was successful."
                IsError = $false
            })
        }
    }
} catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-HTTPError -ErrorObject $ex
        $errorMessage = "Could not delete StudyTube account for: [$($p.DisplayName)]. Error: $($errorObj.ErrorMessage)"
    } else {
        $errorMessage = "Could not delete StudyTube account for: [$($p.DisplayName)]. Error: $($ex.Exception.Message)"
    }
    Write-Verbose $errorMessage
    $auditLogs.Add([PSCustomObject]@{
        Message = $errorMessage
        IsError = $true
    })
} finally {
    $result = [PSCustomObject]@{
        Success   = $success
        Auditlogs = $auditLogs
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
