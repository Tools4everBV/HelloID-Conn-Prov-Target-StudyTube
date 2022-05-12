#####################################################
# HelloID-Conn-Prov-Target-StudyTubeV2-Update
#
# Version: 1.0.0
#####################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $AccountReference | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Account mapping
$account = @{
    # Mandatory properties
    uid                 = $p.ExternalId
    email               = $p.Accounts.MicrosoftActiveDirectory.mail
    first_name          = $p.Name.GivenName
    last_name           = $p.Name.FamilyName

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
    send_invite         = 'false'
    assign_license      = 'false'
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
    if ($dryRun -eq $true) {
        $auditLogs.Add([PSCustomObject]@{
                Message = "Update StudyTubeV2 account for: [$($p.DisplayName)] will be executed during enforcement"
            })
    }

    if (-not($dryRun -eq $true)) {
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

        Write-Verbose 'Updating StudyTubeV2 account'
        $splatUpdateUserParams = @{
            Uri         = "$($config.BaseUrl)/api/v2/users/$aRef"
            Method      = 'PUT'
            Headers     = $headers
            ContentType = 'application/x-www-form-urlencoded'
            Body        = $account
        }
        $updateUserResponse = Invoke-RestMethod @splatUpdateUserParams -verbose:$false
        if ($updateUserResponse) {
            $success = $true
            $auditLogs.Add([PSCustomObject]@{
                    Message = 'Update account was successful'
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
        $errorMessage = "Could not update StudyTubeV2 account. Error: $($errorObj.ErrorMessage)"
    } else {
        $errorMessage = "Could not update StudyTubeV2 account. Error: $($ex.Exception.Message)"
    }
    Write-Verbose $errorMessage
    $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
} finally {
    $result = [PSCustomObject]@{
        Success   = $success
        Account   = $account
        Auditlogs = $auditLogs
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
