#####################################################
# HelloID-Conn-Prov-Target-StudyTube-Permissions
#
# Version: 1.0.0
#####################################################
# Initialize default value's
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
        } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $httpErrorObj.ErrorMessage = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
        }
        Write-Output $httpErrorObj
    }
}
#endregion

try {
    Write-Verbose 'Adding authorization headers'
    $authorization = "$($config.CompanyID):$($config.ApiToken)"
    $base64String = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($authorization))
    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add("Authorization", "Basic $($base64String)")

    Write-Verbose 'Retrieving total pages for the teams resource'
    $splatResourceTotalParams = @{
        Uri     = "$($config.BaseUrl)/v1/users"
        Method  = 'HEAD'
        Headers = $headers
    }
    $null = Invoke-RestMethod @splatResourceTotalParams -ResponseHeadersVariable responseHeaders

    Write-Verbose 'Retrieving all teams from StudyTube'
    $page = 0
    $totalPages = $responseHeaders.'X-Total-Pages'[0] -as [int]
    $teamList = [System.Collections.Generic.List[Object]]::new()
    do {
        $splatGetUserParams = @{
            Uri         = "$($config.BaseUrl)/v1/teams?page=$page"
            Method      = 'GET'
            Headers     = $headers
            ContentType = 'application/json'
        }
        $teamResult = Invoke-RestMethod @splatGetUserParams
        $teamList.AddRange($teamResult)
        $page++
    } until ($page -eq $totalPages)

    $permissionList = [System.Collections.Generic.List[object]]::new()
    foreach ($team in $teamList){
        $permission = @{
            DisplayName = $team.name
            Identification = @{
                DisplayName = $team.name
                Reference = $team.id
            }
        }
        $permissionList.Add($permission)
    }

    Write-Output $permissionList | ConvertTo-Json -Depth 10
} catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-HTTPError -ErrorObject $ex
        $errorMessage = "Could not retrieve StudyTube permissions. Error: $($errorObj.ErrorMessage)"
    } else {
        $errorMessage = "Could not retrieve StudyTube permissions. Error: $($ex.Exception.Message)"
    }
    Write-Verbose $errorMessage
}
