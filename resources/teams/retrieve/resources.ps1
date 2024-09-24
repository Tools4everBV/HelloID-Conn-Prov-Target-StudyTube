####################################################
# HelloID-Conn-Prov-Target-StudyTube-Resources-Teams
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

    Write-Information 'Retrieving Teams from StudyTube'
    $pageSize = [int]$actionContext.Configuration.ResourcePageSize
    $pageNumber = 1

    $returnTeams = [System.Collections.Generic.List[Object]]::new()
    do {
        $splatGetUserParams = @{
            Uri     = "$($actionContext.Configuration.BaseUrl)/api/v2/academy-teams/active?per_page=$($pageSize)&page=$pageNumber"
            Method  = 'GET'
            Headers = $headers
        }
        try {
            $rawTeamsContent = Invoke-RestMethod @splatGetUserParams -Verbose:$false
            $isoEncoding = [System.Text.Encoding]::GetEncoding('ISO-8859-1')
            $partialResultTeams = [System.Text.Encoding]::UTF8.GetString($isoEncoding.GetBytes(($rawTeamsContent | ConvertTo-Json -Depth 10))) | ConvertFrom-json
        } catch {
            if ( $_.Exception.StatusCode -eq 429) {
                throw "TooManyRequests: Hit the rating limit. Please try using a higher ResourcePageSize configuration. The current is [$($actionContext.Configuration.ResourcePageSize)]. The API maximum is 1000."
            } else {
                throw
            }
        }
        if ($partialResultTeams.Count -gt 0) {
            $returnTeams.AddRange($partialResultTeams)
        }
        $pageNumber++
        Write-Information "Teams found [$($returnTeams.Count)]"

    } while ( $partialResultTeams.Count -eq $pageSize )

    Write-Information "Export [$($returnTeams.Count)] users to CSV: [$($actionContext.Configuration.TeamsCsvExportFileAndPath)]"
    $returnTeams | Select-Object id, name, archived, external_id, organizational_unit, created_at | Export-Csv -Path "$($actionContext.Configuration.TeamsCsvExportFileAndPath)" -NoTypeInformation -Force
    $outputContext.Success = $true
} catch {
    $outputContext.Success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-StudyTubeError -ErrorObject $ex
        $auditMessage = "Could not create StudyTube teams resource CSV file. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not create StudyTube teams resource CSV file. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}
