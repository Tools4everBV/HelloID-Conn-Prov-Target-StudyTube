#####################################################
# HelloID-Conn-Prov-Target-StudyTubeV2-Create
#
# Version: 1.0.0
#####################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

#region support functions
function Get-LastName {
    Param (
        [object]$person
    )

    switch ($person.Name.Convention) {
        'B' { 
            if (-not [string]::IsNullOrEmpty($person.Name.familyNamePrefix)) {
                $calcFullName = $calcFullName + $person.Name.familyNamePrefix + ' '
            }
            $calcFullName = $calcFullName + $person.Name.FamilyName
            break 
        }
        'P' { 
            if (-not [string]::IsNullOrEmpty($person.Name.familyNamePartnerPrefix)) {
                $calcFullName = $calcFullName + $person.Name.familyNamePartnerPrefix + ' '
            }
            $calcFullName = $calcFullName + $person.Name.FamilyNamePartner
            break 
        }
        'BP' { 
            if (-not [string]::IsNullOrEmpty($person.Name.familyNamePrefix)) {
                $calcFullName = $calcFullName + $person.Name.familyNamePrefix + ' '
            }
            $calcFullName = $calcFullName + $person.Name.FamilyName + ' - '
            if (-not [string]::IsNullOrEmpty($person.Name.familyNamePartnerPrefix)) {
                $calcFullName = $calcFullName + $person.Name.familyNamePartnerPrefix + ' '
            }
            $calcFullName = $calcFullName + $person.Name.FamilyNamePartner
            break 
        }
        'PB' { 
            if (-not [string]::IsNullOrEmpty($person.Name.familyNamePartnerPrefix)) {
                $calcFullName = $calcFullName + $person.Name.familyNamePartnerPrefix + ' '
            }
            $calcFullName = $calcFullName + $person.Name.FamilyNamePartner + ' - '
            if (-not [string]::IsNullOrEmpty($person.Name.familyNamePrefix)) {
                $calcFullName = $calcFullName + $person.Name.familyNamePrefix + ' '
            }
            $calcFullName = $calcFullName + $person.Name.FamilyName
            break 
        }
        Default {
            if (-not [string]::IsNullOrEmpty($person.Name.familyNamePrefix)) {
                $calcFullName = $calcFullName + $person.Name.familyNamePrefix + ' '
            }
            $calcFullName = $calcFullName + $person.Name.FamilyName
            break 
        }
    } 
    return $calcFullName
}
#endregion support functions

# Account mapping
$account = @{
    # Mandatory properties
    uid                 = $p.ExternalId
    email               = $p.Accounts.MicrosoftActiveDirectory.mail
    first_name          = $p.Name.NickName
    last_name           = Get-LastName -person $p

    # Optional properties
    company_role        = $p.PrimaryContract.Title.Name

    # Available: en,nl,fi,fr,es,de,pt,pl
    language            = 'nl'
    phone_number        = $p.Contact.Business.Phone.Fixed
    linkedin_url        = ''

    # Avatar must be a png,jpg,jpeg file. Max 20MB
    avatar              = ''
    gender              = ''
    date_of_birth       = $p.Details.BirthDate
    house_number        = ''
    postal_code         = ''
    city                = ''
    place_of_birth      = ''
    employee_number     = $p.ExternalId
    address             = ''
    cost_centre         = ''
    send_invite         = 'false'   # send mail on create
    assign_license      = 'false'   # extra license (content license). Default license is autmaticaly assgined by StudyTube.
    contract_start_date = ''
    contract_end_date   = ''
}

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

#set User Page Size
$userPageSize = $config.userPageSize

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

# Begin
try {
    $action = "Create"
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

    Write-Verbose 'Retrieving total pages for the user resource'
    $splatResourceTotalParams = @{
        Uri     = "$($config.BaseUrl)/api/v2/users?perPage=$userPageSize"
        Method  = 'HEAD'
        Headers = $headers
    }
    $null = Invoke-RestMethod @splatResourceTotalParams -ResponseHeadersVariable responseHeaders -verbose:$false

    # Verify if a user must be either [created and correlated], [updated and correlated] or just [correlated]
    Write-Verbose 'Retrieving all users from StudyTube'
    $page = 0
    $totalPages = $responseHeaders.'X-Total-Pages'[0] -as [int]
    $userList = [System.Collections.Generic.List[Object]]::new()
    do {
        $splatGetUserParams = @{
            Uri         = "$($config.BaseUrl)/api/v2/users?page=$page&perPage=$userPageSize"
            Method      = 'GET'
            Headers     = $headers
            ContentType = 'application/json'
        }
        $userResult = Invoke-RestMethod @splatGetUserParams
        $userList.AddRange($userResult)
        $page++
    } until ($page -eq $totalPages)

    Write-Verbose "Verify if StudyTube account for: [$($p.DisplayName)] must be created or correlated"

    # In some cases studytube returns the same userid multiple times (exactly the same record).
    $userList = $userList | Sort-Object id -Unique

    $lookupUser = $userList | Group-Object -Property uid -AsHashTable -AsString
    $responseUser = $lookupUser[$account.uid]
    if (($responseUser | measure-object).Count -gt 1) {
        Throw "Found multiple user accounts [$($responseUser.email -join ", ")] [$($responseUser.id -join ", ")]"
    }

    if (-not($responseUser)) {
        $action = 'Create-Correlate'
    }
    elseif ($($config.UpdatePersonOnCorrelate -eq "true")) {
        $action = 'Update-Correlate'
    }
    else {
        $action = 'Correlate'
    }

    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true) {
        $auditLogs.Add([PSCustomObject]@{
                Message = "$action StudyTubeV2 account for: [$($p.DisplayName)], will be executed during enforcement"
            })
    }

    # Process
    if (-not($dryRun -eq $true)) {
        switch ($action) {
            'Create-Correlate' {
                Write-Verbose "Creating and correlating StudyTubeV2 account"
                $splatCreateUserParams = @{
                    Uri         = "$($config.BaseUrl)/api/v2/users"
                    Method      = 'POST'
                    Headers     = $headers
                    ContentType = 'application/x-www-form-urlencoded'
                    Body        = $account
                }
                $createUserResponse = Invoke-RestMethod @splatCreateUserParams -verbose:$false
                $accountReference = $createUserResponse.id
                break
            }

            'Update-Correlate' {
                Write-Verbose "Updating and correlating StudyTubeV2 account"
                $splatUpdateUserParams = @{
                    Uri         = "$($config.BaseUrl)/api/v2/users/$($responseUser.Id)"
                    Method      = 'PUT'
                    Headers     = $headers
                    ContentType = 'application/x-www-form-urlencoded'
                    Body        = $account
                }
                $updateUserResponse = Invoke-RestMethod @splatUpdateUserParams -verbose:$false
                $accountReference = $updateUserResponse.id
                break
            }

            'Correlate' {
                Write-Verbose "Correlating StudyTube account for: [$($p.DisplayName)]"
                $accountReference = $responseUser.id
                break
            }
        }

        $success = $true
        $auditLogs.Add([PSCustomObject]@{
                Message = "$action account was successful. AccountReference is: [$accountReference]"
                IsError = $false
            })
    }
}
catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-HTTPError -ErrorObject $ex
        $errorMessage = "Could not $action StudyTubeV2 account. Error: $($errorObj.ErrorMessage)"
    }
    else {
        $errorMessage = "Could not $action StudyTubeV2 account. Error: $($ex.Exception.Message)"
    }
    Write-Verbose $errorMessage
    $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
    # End
}
finally {
    $result = [PSCustomObject]@{
        Success          = $success
        AccountReference = $accountReference
        Auditlogs        = $auditLogs
        Account          = $account
        ExportData       = [PSCustomObject]@{
            id = $accountReference
        }
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}