######################################################
# HelloID-Conn-Prov-Target-StudyTube-Permissions
# PowerShell V2
######################################################

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
    Write-Verbose 'Retrieving authorization token'
    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add("Content-Type", "application/x-www-form-urlencoded")
    $tokenBody = @{
        client_id     = $($actionContext.Configuration.ClientId)
        client_secret = $($actionContext.Configuration.ClientSecret)
        grant_type    = 'client_credentials'
        scope         = 'read write'
    }
    $tokenResponse = Invoke-RestMethod -Uri "$($actionContext.Configuration.TokenUrl)/gateway/oauth/token" -Method 'POST' -Headers $headers -Body $tokenBody -verbose:$false

    Write-Verbose 'Setting authorization header'
    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add('Authorization', "Bearer $($tokenResponse.access_token)")

    Write-Information 'Retrieving all active academy-teams from StudyTube'
    $pageSize = [int]$actionContext.Configuration.ResourcePageSize
    $pageNumber = 1

    $teamResult = [System.Collections.Generic.List[Object]]::new()
    do {
        try {
            $splatRetrievePermissionsParams = @{
                Uri         = "$($actionContext.Configuration.BaseUrl)/api/v2/academy-teams/active?per_page=$($pageSize)&page=$pageNumber"
                Method      = 'GET'
                Headers     = $headers
                ContentType = 'application/json'
            }
            $rawTeamsContent = Invoke-RestMethod @splatRetrievePermissionsParams -Verbose:$false
            $isoEncoding = [System.Text.Encoding]::GetEncoding('ISO-8859-1')
            $partialTeamResult = [System.Text.Encoding]::UTF8.GetString($isoEncoding.GetBytes(($rawTeamsContent | ConvertTo-Json -Depth 10))) | ConvertFrom-json
        } catch {
            if ( $_.Exception.StatusCode -eq 429) {
                throw "TooManyRequests: Hit the rating limit. Please try using a higher ResourcePageSize configuration. The current is [$($actionContext.Configuration.ResourcePageSize)]. The API maximum is 1000."
            } else {
                throw
            }
        }
        if ($partialTeamResult.Count -gt 0) {
            $teamResult.AddRange($partialTeamResult)
        }
        $pageNumber++
        Write-Information "Teams found [$($teamResult.Count)]"
    } while ( $partialTeamResult.Count -eq $pageSize )

    foreach ($team in $teamResult) {
        $outputContext.Permissions.Add( @{
                DisplayName    = $team.name
                Identification = @{
                    DisplayName = $team.name
                    Reference   = $team.id
                }
            }
        )
    }
} catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-StudyTubeError -ErrorObject $ex
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
}
