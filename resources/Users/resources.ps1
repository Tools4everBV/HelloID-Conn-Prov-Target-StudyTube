####################################################
# HelloID-Conn-Prov-Target-StudyTube-Resources-Users
# PowerShell V2
####################################################

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

try {
    Write-Information 'Retrieving authorization token'
    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add('Content-Type', 'application/x-www-form-urlencoded')
    $tokenBody = @{
        client_id     = $($actionContext.Configuration.ClientId)
        client_secret = $($actionContext.Configuration.ClientSecret)
        grant_type    = 'client_credentials'
        scope         = 'read write'
    }
    $tokenResponse = Invoke-RestMethod -Uri "$($actionContext.Configuration.TokenUrl)/gateway/oauth/token" -Method 'POST' -Headers $headers -Body $tokenBody -Verbose:$false

    Write-Information 'Setting authorization header'
    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add('Authorization', "Bearer $($tokenResponse.access_token)")

    Write-Information 'Retrieving Users from StudyTube'
    $pageSize = [int]$actionContext.Configuration.ResourcePageSize
    $pageNumber = 1

    $returnUsers = [System.Collections.Generic.List[Object]]::new()
    do {
        $splatGetUserParams = @{
            Uri     = "$($actionContext.Configuration.BaseUrl)/api/v2/users?per_page=$($pageSize)&page=$pageNumber"
            Method  = 'GET'
            Headers = $headers
        }
        try {
            $partialResultUsers = Invoke-RestMethod @splatGetUserParams -Verbose:$false

        } catch {
            if ( $_.Exception.StatusCode -eq 429) {
                throw "TooManyRequests: Hit the rating limit. Please try using a higher ResourcePageSize configuration. The current is [$($actionContext.Configuration.ResourcePageSize)]. The API maximum is 1000."
            } else {
                throw
            }
        }
        if ($partialResultUsers.Count -gt 0) {
            $returnUsers.AddRange($partialResultUsers)
        }
        $pageNumber++
        Write-Information "Users found [$($returnUsers.Count)]"

    } while ( $partialResultUsers.Count -eq $pageSize )

    Write-Information "Export [$($returnUsers.Count)] users to CSV [$($actionContext.Configuration.CsvExportFileAndPath)]"
    $returnUsers | Select-Object id, full_name, uid, employee_number, email | Export-Csv -Path "$($actionContext.Configuration.CsvExportFileAndPath)" -NoTypeInformation -Force
    $outputContext.Success = $true
} catch {
    $outputContext.Success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-StudyTubeError -ErrorObject $ex
        $auditMessage = "Could not create StudyTube resource. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not create StudyTube resource. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}
