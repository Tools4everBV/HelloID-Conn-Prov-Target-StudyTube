#####################################################
# HelloID-Conn-Prov-Target-StudyTubeV2-Permissions
#
# Version: 1.1.0
#####################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json

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

    Write-Verbose 'Retrieving all active academy-teams from StudyTube'
    $splatGetUserParams = @{
        Uri         = "$($config.BaseUrl)/api/v2/academy-teams/active"
        Method      = 'GET'
        Headers     = $headers
        ContentType = 'application/json'
    }
    $teamResult = Invoke-RestMethod @splatGetUserParams

    $permissionList = [System.Collections.Generic.List[object]]::new()
    foreach ($team in $teamResult) {
        $permission = @{
            DisplayName    = $team.name
            Identification = @{
                DisplayName = $team.name
                Reference   = $team.id
            }
        }
        $permissionList.Add($permission)
    }

    Write-Output $permissionList | ConvertTo-Json -Depth 10
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-HTTPError -ErrorObject $ex
        $errorMessage = "Could not retrieve StudyTubeV2 permissions. Error: $($errorObj.ErrorMessage)"
    }
    else {
        $errorMessage = "Could not retrieve StudyTubeV2 permissions. Error: $($ex.Exception.Message)"
    }
    Write-Verbose $errorMessage
}