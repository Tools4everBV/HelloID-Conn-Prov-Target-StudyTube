###########################################################
# HelloID-Conn-Prov-Target-StudyTube-Resources-Teams-Create
# PowerShell V2
###########################################################

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
            $partialTeamResult = Invoke-RestMethod @splatRetrievePermissionsParams -Verbose:$false
        } catch {
            if ( $_.Exception.StatusCode -eq 429) {
                throw "TooManyRequests: Hit the rating limit. Please try using a higher ResourcePageSize configuration. The current is [$($actionContext.Configuration.ResourcePageSize)]. The API maximum is 1000."
            } else {
                throw "Error retrieving teams: $($_)"
            }
        }
        if ($partialTeamResult.Count -gt 0) {
            $teamResult.AddRange($partialTeamResult)
        }
        $pageNumber++
        Write-Information "Teams found [$($teamResult.Count)] | page: $pageNumber"
    } while ( $partialTeamResult.Count -eq $pageSize )

    $isoEncoding = [System.Text.Encoding]::GetEncoding('ISO-8859-1')
    $teamResult = [System.Text.Encoding]::UTF8.GetString($isoEncoding.GetBytes(($teamResult | ConvertTo-Json -Depth 10))) | ConvertFrom-json

    Write-Warning "Teams found in StudyTube: $(($teamResult | measure-object).count)"

    #Write-Warning "$(($teamResult | where-object name -like "Stagiaire V&V niv.1/2 * NIET GEBRUIKEN & NOVA-PG *").name)"

    Write-Information 'Validating resources that will need to be created'
    $resourcesToCreate = [System.Collections.Generic.List[object]]::new()
    $teamResultGrouped = $teamResult | Group-Object -AsString -AsHashTable -Property name

    foreach ($resource in $resourceContext.SourceData) {

        if(-not([string]::IsNullOrEmpty($resource))){
            $exists = $teamResultGrouped["$($resource)"]
            if ($null -eq $exists) {
                $resourcesToCreate.Add($resource)
            }
        }
    }
    Write-Information "Creating [$($resourcesToCreate.Count)] resources"

    foreach ($resource in $resourcesToCreate) {
        try {
            if (-not ($actionContext.DryRun -eq $True)) {
                $splatCreateResourceParams = @{
                    Uri         = "$($actionContext.Configuration.BaseUrl)/api/v2/academy-teams"
                    Method      = 'POST'
                    Headers     = $headers
                    ContentType = 'application/x-www-form-urlencoded'
                    Body        = @{
                        name = $resource
                    }
                }
                $null = Invoke-RestMethod @splatCreateResourceParams -Verbose:$false
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Created resource: [$($resource)]"
                        IsError = $false
                    })
            } else {
                Write-Information "[DryRun] Create [$($resource)] StudyTube resource, will be executed during enforcement"
            }
        } catch {
            $outputContext.Success = $false
            $ex = $PSItem
            if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
                $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
                $errorObj = Resolve-StudyTubeError -ErrorObject $ex
                $auditMessage = "Could not create StudyTube resource [$($resource)]. Error: $($errorObj.FriendlyMessage)"
                Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
            } else {
                $auditMessage = "Could not create StudyTube resource [$($resource)]. Error: $($ex.Exception.Message)"
                Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
            }
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = $auditMessage
                    IsError = $true
                })
        }
    }
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
