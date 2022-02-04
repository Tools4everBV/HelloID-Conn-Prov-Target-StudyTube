#####################################################
# HelloID-Conn-Prov-Target-StudyTube-Update
#
# Version: 1.0.0
#####################################################
# Initialize default value's
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $AccountReference | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Account mapping
$account = [ordered]@{
    user_id         = $p.ExternalId
    email           = $p.Contact.Business.Email
    first_name      = 'David'
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

try {
    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true){
        $auditLogs.Add([PSCustomObject]@{
            Message = "Update StudyTube account for: [$($p.DisplayName)], will be executed during enforcement"
        })
    }

    if (-not($dryRun -eq $true)) {
        Write-Verbose "Updating StudyTube account: [$aRef] for: [$($p.DisplayName)]"
        Write-Verbose 'Adding authorization headers'
        $authorization = "$($config.CompanyID):$($config.ApiToken)"
        $base64String = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($authorization))
        $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
        $headers.Add("Authorization", "Basic $($base64String)")

        $splatUpdateUserParams = @{
            Uri         = "$($config.BaseUrl)/v1/users/$aRef"
            Method      = 'PATCH'
            Headers     = $headers
            ContentType = 'application/json'
            Body        = $account | ConvertTo-Json
        }
        $null = Invoke-RestMethod @splatUpdateUserParams

        $success = $true
        $auditLogs.Add([PSCustomObject]@{
            Message = "Update account for: [$($p.DisplayName)] was successful."
            IsError = $false
        })
    }
} catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-HTTPError -ErrorObject $ex
        $errorMessage = "Could not update StudyTube account for: [$($p.DisplayName)]. Error: $($errorObj.ErrorMessage)"
    } else {
        $errorMessage = "Could not update StudyTube account for: [$($p.DisplayName)]. Error: $($ex.Exception.Message)"
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
