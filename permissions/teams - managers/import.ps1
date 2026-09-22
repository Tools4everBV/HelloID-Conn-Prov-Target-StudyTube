####################################################################
# HelloID-Conn-Prov-Target-StudyTube-ImportPermissions-Teams-Managers
# PowerShell V2
####################################################################

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
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
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
        }
        catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
        }
        Write-Output $httpErrorObj
    }
}
#endregion

try {
    Write-Information 'Starting StudyTube permission entitlement import'

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
    # Rate limit: max 90 requests per minute
    Start-Sleep -Milliseconds 750

    Write-Information 'Setting authorization header'
    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add('Authorization', "Bearer $($tokenResponse.access_token)")

    Write-Information 'Retrieving all active academy-teams from StudyTube'
    $pageSize = [int]$actionContext.Configuration.ResourcePageSize
    $pageNumber = 1

    do {
        $splatGetTeamsParams = @{
            Uri     = "$($actionContext.Configuration.BaseUrl)/api/v2/academy-teams/active?per_page=$($pageSize)&page=$pageNumber"
            Method  = 'GET'
            Headers = $headers
        }
        try {
            $rawTeamsContent = Invoke-RestMethod @splatGetTeamsParams -Verbose:$false
            # Rate limit: max 90 requests per minute
            Start-Sleep -Milliseconds 750
            $isoEncoding = [System.Text.Encoding]::GetEncoding('ISO-8859-1')
            if ($null -eq $rawTeamsContent -or ($rawTeamsContent -is [string] -and [string]::IsNullOrWhiteSpace($rawTeamsContent)) -or $rawTeamsContent.Count -eq 0) {
                $partialResultTeams = @()
            }
            else {
                $partialResultTeams = [System.Text.Encoding]::UTF8.GetString($isoEncoding.GetBytes(($rawTeamsContent | ConvertTo-Json -Depth 10))) | ConvertFrom-Json
            }
        }
        catch {
            if ($_.Exception.StatusCode -eq 429) {
                throw "TooManyRequests: Hit the rating limit. Please try using a higher ResourcePageSize configuration. The current is [$($actionContext.Configuration.ResourcePageSize)]. The API maximum is 1000."
            }
            else {
                throw
            }
        }

        foreach ($team in $partialResultTeams) {
            $pageNumberTeamMembers = 1
            do {              
                $splatGetTeamManagers = @{
                    Uri     = "$($actionContext.Configuration.BaseUrl)/api/v2/academy-teams/$($team.id)/managers?per_page=$($pageSize)&page=$pageNumberTeamMembers"
                    Method  = 'GET'
                    Headers = $headers
                }
                    
                $rawTeamManagersContent = Invoke-RestMethod @splatGetTeamManagers -Verbose:$false
                # Rate limit: max 90 requests per minute
                Start-Sleep -Milliseconds 750

                $isoEncoding = [System.Text.Encoding]::GetEncoding('ISO-8859-1')
                if ($null -eq $rawTeamManagersContent -or ($rawTeamManagersContent -is [string] -and [string]::IsNullOrWhiteSpace($rawTeamManagersContent)) -or $rawTeamManagersContent.Count -eq 0) {
                    $partialResultTeamManagers = @()
                }
                else {
                    $partialResultTeamManagers = [System.Text.Encoding]::UTF8.GetString($isoEncoding.GetBytes(($rawTeamManagersContent | ConvertTo-Json -Depth 10))) | ConvertFrom-Json
                }
                $teamManagers = @($partialResultTeamManagers.user.id)
                $permission = @{
                    PermissionReference = @{
                        Reference = $team.id
                        Type      = 'Manager'
                    }
                    AccountReferences   = @()
                }

                if (($teamManagers | Measure-Object).Count -gt 0) {
                    # Batches of 500 account references are returned to prevent exceeding the maximum limit per batch
                    $batchSize = 500
                    for ($i = 0; $i -lt $teamManagers.Count; $i += $batchSize) {
                        $permission.AccountReferences = @($teamManagers[$i..([Math]::Min($i + $batchSize - 1, $teamManagers.Count - 1))])
                        Write-Output $permission
                    }
                }
            } while ($partialResultTeamManagers.Count -eq $pageSize)
        }
        $pageNumber++
    } while ($partialResultTeams.Count -eq $pageSize)
    Write-Information 'StudyTube permission entitlement import for managers completed'
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-StudyTubeError -ErrorObject $ex
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
        Write-Error "Could not import StudyTube permission entitlements. Error: $($errorObj.FriendlyMessage)"
    }
    else {
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        Write-Error "Could not import StudyTube permission entitlements. Error: $($ex.Exception.Message)"
    }
}
