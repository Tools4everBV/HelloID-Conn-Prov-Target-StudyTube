#######################################################
# HelloID-Conn-Prov-Target-StudyTube-Create
#
# Version: 1.0.0.0
#######################################################
$VerbosePreference = "Continue"

# Initialize default value's
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$success = $false
$auditLogs = New-Object Collections.Generic.List[PSCustomObject]

$account = [PSCustomObject]@{
    user_id         = $p.PersonId
    employee_number = ''
    email           = $p.Contact.Business.Email
    first_name      = $p.Name.GivenName
    last_name       = $p.Name.FamilyName
    language        = 'nl_NL'
    date_of_birth   = $p.Details.BirthDate
    company_role    = $CompanyRole
    phone_number    = $p.Contact.Business.Phone.Fixed
    address         = $p.Contact.Business.Address.Street
    house_number    = $p.Contact.Business.Address.HouseNumber
    postal_code     = $p.Contact.Business.Address.PostalCode
    city            = $p.Contact.Business.Address.Locality
    place_of_birth  = $p.Details.BirthLocality
    send_invite     = ''
    content_licence = ''
    cost_centre     = ''
} | ConvertTo-Json

#region Helper Functions
function Invoke-StudyTubePagedRestMethod {
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[object]])]
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $TotalItems,

        [Parameter(Mandatory = $true)]
        [string]
        $TotalPages,

        [Parameter(Mandatory = $true)]
        [string]
        $Url,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]
        $Headers
    )

    [System.Collections.Generic.List[object]]$dataList = @()
    $page = 1

    do {
        $result = Invoke-RestMethod -Uri $Url -Method GET -Headers $headers
        foreach ($user in $result){
            $dataList.Add($user)
        }
        $page++
    } until (($page -gt $TotalPages) -or ($dataList.Count -gt ($TotalItems - 1)) )

    Write-Output $dataList
}

function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $HttpErrorObj = @{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
        }
        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $HttpErrorObj['ErrorMessage'] = $ErrorObject.ErrorDetails.Message
        } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $stream = $ErrorObject.Exception.Response.GetResponseStream()
            $stream.Position = 0
            $streamReader = New-Object System.IO.StreamReader $Stream
            $errorResponse = $StreamReader.ReadToEnd()
            $HttpErrorObj['ErrorMessage'] = $errorResponse
        }
        Write-Output "'$($HttpErrorObj.ErrorMessage)', TargetObject: '$($HttpErrorObj.RequestUri), InvocationCommand: '$($HttpErrorObj.MyCommand)"
    }
}
#endregion

if (-not($dryRun -eq $true)) {
    try {
        Write-Verbose "Creating account for '$($p.DisplayName)'"

        if ($($config.IsConnectionTls12)) {
            Write-Verbose 'Switching to TLS 1.2'
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
        }

        Write-Verbose 'Adding Authorization headers'
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($($config.ApiToken))
        $apiTokenString = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        $authorization = "$($config.CompanyID):$($apiTokenString)"
        $base64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($authorization))

        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers.Add("Authorization", "Bearer $base64")

        Write-Verbose "Checking if account for '$($p.DisplayName)' already exists"
        Write-Verbose 'Retrieving total items in StudyTube'
        $splatGetTotalItems = @{
            Uri     = "$($config.baseUrl)/v1/users"
            Method  = 'HEAD'
            Headers = $headers
        }
        $responseHeaders = Invoke-RestMethod @splatGetTotalItems
        $totalItems = $totalResults.xTotal = $responseHeaders.Headers.'X-Total'
        $totalPages = $totalResults.xTotalPages = $responseHeaders.Headers.'X-Total-Pages'

        Write-Verbose 'Retrieving paged results'
        $splatGetAllUsers = @{
            Uri        = "$($config.baseUrl)/v1/users"
            TotalItems = $totalItems
            TotalPages = $totalPages
            Headers    = $headers
        }
        $allUsers = Invoke-StudyTubePagedRestMethod @splatGetAllUsers
        $lookup = $allUsers | Group-Object -Property employee_number
        $checkIfUserExists = $lookup[$account.employee_number]
        if ($checkIfUserExists){
            $accountReference = $checkIfUserExists.id
            $logMessage = "Account for user '$($p.DisplayName)' found. Correlation id: '$accountReference'"
            Write-Verbose $logMessage
            $success = $true
            $auditLogs.Add([PSCustomObject]@{
                Message = $logMessage
                IsError = $False
            })
        } else {
            Write-Verbose "Account for user '$($p.DisplayName)' does not exist, proceeding with creating account"
            $splatParams = @{
                Uri      = "$($config.BaseUrl)/v1/users"
                Headers  = $headers
                Body     = $account | ConvertTo-Json
                Method   = 'POST'
            }
            $results = Invoke-RestMethod @splatParams

            $accountReference = $results.id
            $logMessage = "Account for '$($p.DisplayName)' successfully created. Correlation id: '$accountReference'"
            Write-Verbose $logMessage
            $success = $true
            $auditLogs.Add([PSCustomObject]@{
                Message = $logMessage
                IsError = $False
            })
        }
    } catch {
        $ex = $PSItem
        if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $errorMessage = Resolve-HTTPError -Error $ex
            $auditMessage = "Account for '$($p.DisplayName)' not created. Error: $errorMessage"
        } else {
            $auditMessage = "Account for '$($p.DisplayName)' not created. Error: $($ex.Exception.Message)"
        }
        $auditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
        Write-Error $auditMessage
    }
}

$result = [PSCustomObject]@{
    Success          = $success
    Account          = $account
    AccountReference = $accountReference
    AuditLogs        = $auditLogs
}

Write-Output $result | ConvertTo-Json -Depth 10
