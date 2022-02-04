#####################################################
# HelloID-Conn-Prov-Target-StudyTube-Create
#
# Version: 1.0.0
#####################################################
# Initialize default value's
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Account mapping
$account = [ordered]@{
    user_id         = $p.ExternalId
    email           = $p.Contact.Business.Email
    first_name      = $p.Name.GivenName
    last_name       = $p.Name.FamilyName
    language        = 'nl'
    date_of_birth   = $p.Details.BirthDate
    company_role    = $p.PrimaryContract.Title.Name
    phone_number    = $p.Contact.Business.Phone.Fixed
    address         = ''
    house_number    = ''
    postal_code     = ''
    city            = $City
    place_of_birth  = ''
    send_invite     = 'false'
    content_licence = 'false'
    employee_number = $p.ExternalId
    cost_centre     = ''
}

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

# Begin
try {
    Write-Verbose 'Adding authorization headers'
    $authorization = "$($config.CompanyID):$($config.ApiToken)"
    $base64String = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($authorization))
    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add("Authorization", "Basic $($base64String)")

    Write-Verbose 'Retrieving total pages for the user resource'
    $splatResourceTotalParams = @{
        Uri     = "$($config.BaseUrl)/v1/users"
        Method  = 'HEAD'
        Headers = $headers
    }
    $null = Invoke-RestMethod @splatResourceTotalParams -ResponseHeadersVariable responseHeaders

    Write-Verbose 'Retrieving all users from StudyTube'
    $page = 0
    $totalPages = $responseHeaders.'X-Total-Pages'[0] -as [int]
    $userList = [System.Collections.Generic.List[Object]]::new()
    do {
        $splatGetUserParams = @{
            Uri         = "$($config.BaseUrl)/v1/users?page=$page"
            Method      = 'GET'
            Headers     = $headers
            ContentType = 'application/json'
        }
        $userResult = Invoke-RestMethod @splatGetUserParams
        $userList.AddRange($userResult)
        $page++
    } until ($page -eq $totalPages)

    Write-Verbose "Verify if StudyTube account for: [$($p.DisplayName)] must be created or correlated"
    $lookupUser = $userList | Group-Object -Property user_id -AsHashTable -AsString
    $studyTubeUser = $lookupUser[$account.user_id]

    if ($studyTubeUser){
        $action = 'Correlate'
    } else {
        $action = 'Create'
    }

    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true){
        $auditLogs.Add([PSCustomObject]@{
            Message = "$action StudyTube account for: [$($p.DisplayName)], will be executed during enforcement"
        })
    }

    # Process
    if (-not($dryRun -eq $true)){
        switch ($action) {
            'Create' {
                Write-Verbose "Creating StudyTube account for: [$($p.DisplayName)]"
                $splatCreateUserParams = @{
                    Uri         = "$($config.BaseUrl)/v1/users"
                    Method      = 'POST'
                    Headers     = $headers
                    ContentType = 'application/json'
                    Body        = $account | ConvertTo-Json
                }
                $createUserResponse = Invoke-RestMethod @splatCreateUserParams
                $accountReference = $createUserResponse.id
                break
            }

            'Correlate'{
                Write-Verbose "Correlating StudyTube account for: [$($p.DisplayName)]"
                $accountReference = $studyTubeUser.id
                break
            }
        }

        $success = $true
        $auditLogs.Add([PSCustomObject]@{
            Message = "$action account for: [$($p.DisplayName)] was successful. accountReference is: [$accountReference]"
            IsError = $false
        })
    }
} catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-HTTPError -ErrorObject $ex
        $errorMessage = "Could not $action StudyTube account for: [$($p.DisplayName)]. Error: $($errorObj.ErrorMessage)"
    } else {
        $errorMessage = "Could not $action StudyTube account for: [$($p.DisplayName)]. Error: $($ex.Exception.Message)"
    }
    Write-Verbose $errorMessage
    $auditLogs.Add([PSCustomObject]@{
        Message = $errorMessage
        IsError = $true
    })
# End
} finally {
   $result = [PSCustomObject]@{
        Success          = $success
        AccountReference = $accountReference
        Auditlogs        = $auditLogs
        Account          = $account
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
