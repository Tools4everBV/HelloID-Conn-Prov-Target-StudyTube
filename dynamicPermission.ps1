#####################################################
# HelloID-Conn-Prov-Target-StudyTubeV2-Entitlement-DynamicPermission
#
# Version: 1.1.0
#####################################################

#region Initialize default properties
$config = ConvertFrom-Json $configuration
$p = $person | ConvertFrom-Json
$pp = $previousPerson | ConvertFrom-Json
$pd = $personDifferences | ConvertFrom-Json
$m = $manager | ConvertFrom-Json
$aRef = $accountReference | ConvertFrom-Json
$mRef = $managerAccountReference | ConvertFrom-Json

$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Operation is a script parameter which contains the action HelloID wants to perform for this permission
# It has one of the following values: "grant", "revoke", "update"
$o = $operation | ConvertFrom-Json

# The permissionReference contains the Identification object provided in the retrieve permissions call
$pRef = $permissionReference | ConvertFrom-Json

# The entitlementContext contains the sub permissions (Previously the $permissionReference variable)
$eRef = $entitlementContext | ConvertFrom-Json

$currentPermissions = @{}
foreach ($permission in $eRef.CurrentPermissions) {
    $currentPermissions[$permission.Reference.Id] = $permission.DisplayName
}

# # Determine all the sub-permissions that needs to be Granted/Updated/Revoked
$subPermissions = [Collections.Generic.List[PSCustomObject]]::new()

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
    # Make Name the grouped value to search with the correlationValue
    $teamLookup = $teamResult | Group-Object -Property Name -AsHashTable -AsString

    # #region Change mapping here
    $desiredPermissions = @{}
    if ($o -ne "revoke") {
        # Example: Contract Based Logic:
        foreach ($contract in $p.Contracts) {
            Write-Verbose ("Contract in condition: {0}" -f $contract.Context.InConditions)
            if ($contract.Context.InConditions -OR ($dryRun -eq $True)) {

                # Example of correlation value. Change this value to your needs
                $correlationValue = $contract.Department.DisplayName + " " + $contract.Title.Name

                # Search the team name with the correlatioValue
                $teamResponse = $teamLookup[$correlationValue]

                if ($teamResponse.Id.count -eq 0) {
                    write-warning "No Team found that matches filter [$($correlationValue)]"
                    throw "No Team found that matches filter [$($correlationValue)]"
                }
                elseif ($teamResponse.Id.count -gt 1) {
                    write-warning "Multiple Teams found that matches filter [$($correlationValue)]. Please correct this so the teams are unique."
                    throw "Multiple Teams found that matches filter [$($correlationValue)]. Please correct this so the teams are unique."
                }

                # # Add group to desired permissions with the id as key and the name as value
                $desiredPermissions["$($teamResponse.id)"] = $teamResponse.name
            }
        }
    }

    Write-Information ("Desired Permissions: {0}" -f ($desiredPermissions.Values | ConvertTo-Json))

    Write-Information ("Existing Permissions: {0}" -f ($eRef.CurrentPermissions.DisplayName | ConvertTo-Json))
    #endregion Change mapping here

    #region Execute
    # Compare desired with current permissions and grant permissions
    foreach ($permission in $desiredPermissions.GetEnumerator()) {
        $subPermissions.Add([PSCustomObject]@{
                DisplayName = $permission.Value
                Reference   = [PSCustomObject]@{ Id = $permission.Name }
            })

        if (-Not $currentPermissions.ContainsKey($permission.Name)) {
            # Grant AD Groupmembership
            try {
                if ($dryRun -eq $false) {
                    Write-Verbose "Granting StudyTubeV2 entitlement: [($($permission.Value))] [$($permission.Name)] for user: [$aRef]"

                    $splatGrantPermissionParams = @{
                        Uri         = "$($config.BaseUrl)/api/v2/academy-teams/$($permission.Name)/users"
                        Method      = 'POST'
                        Headers     = $headers
                        ContentType = 'application/x-www-form-urlencoded'
                        Body        = @{
                            academyTeamId = $permission.Name
                            user_id       = $aRef
                        }
                    }
                    $grantPermissionsResponse = Invoke-RestMethod @splatGrantPermissionParams -verbose:$false
                    if ($grantPermissionsResponse) {
                        $auditLogs.Add([PSCustomObject]@{
                                Action  = "GrantPermission"
                                Message = "Successfully granted StudyTubeV2 entitlement for team [($($permission.Value))] [$($permission.Name)] for user: [$aRef]"
                                IsError = $false
                            })
                    }
                }
                else {
                    Write-Warning "DryRun: Would grant permission to team [($($permission.Value))] [$($permission.Name)] for user: [$aRef]"
                }
            }
            catch {
                $ex = $PSItem
                if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
                    $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
                    $errorObj = Resolve-HTTPError -ErrorObject $ex
                    $errorMessage = "Error granting StudyTubeV2 entitlement for team [($($permission.Value))] [$($permission.Name)] for user: [$aRef]. Error: $($errorObj.ErrorMessage)"
                }
                else {
                    $errorMessage = "Error granting StudyTubeV2 entitlement for team [($($permission.Value))] [$($permission.Name)] for user: [$aRef]. Error: $($ex.Exception.Message)"
                }
                Write-Verbose $errorMessage
                $auditLogs.Add([PSCustomObject]@{
                        Action  = "GrantPermission"    
                        Message = $errorMessage
                        IsError = $true
                    })
            }
        }    
    }

    # Compare current with desired permissions and revoke permissions
    $newCurrentPermissions = @{}
    foreach ($permission in $currentPermissions.GetEnumerator()) {    
        if (-Not $desiredPermissions.ContainsKey($permission.Name) -AND $permission.Name -ne "No Teams Defined") {
            # Revoke AD Groupmembership
            try {
                if ($dryRun -eq $false) {
                    Write-Verbose "Revoking StudyTubeV2 entitlement: [($($permission.Value))] [$($permission.Name)] for user: [$aRef]"

                    $splatRevokePermissionParams = @{
                        Uri         = "$($config.BaseUrl)/api/v2/academy-teams/$($permission.Name)/users"
                        Method      = 'DELETE'
                        Headers     = $headers
                        ContentType = 'application/x-www-form-urlencoded'
                        Body        = @{
                            academyTeamId = $permission.Name
                            user_id       = $aRef
                        }
                    }           
                    try {
                        $null = Invoke-RestMethod @splatRevokePermissionParams -StatusCodeVariable statusCode -verbose:$false
                        if ($statusCode -eq 204) {
                            $auditLogs.Add([PSCustomObject]@{
                                    Action  = "RevokePermission"
                                    Message = "Successfully revoked StudyTubeV2 entitlement for team [($($permission.Value))] [$($permission.Name)] for user: [$aRef]"
                                    IsError = $false
                                })
                        }
                        else {
                            throw
                        }
                    }
                    catch {
                        # A '404'NotFound is returned if the entity cannot be found
                        if ($_.Exception.Response.StatusCode -eq 404) {
                            $auditLogs.Add([PSCustomObject]@{
                                    Action  = "RevokePermission"
                                    Message = "Successfully revoked StudyTubeV2 entitlement for team [($($permission.Value))] [$($permission.Name)] for user: [$aRef] (already removed)"
                                    IsError = $false
                                })
                        }
                        else {
                            throw
                        }
                    }
                }
                else {
                    Write-Warning "DryRun: Would revoke permission from team [($($permission.Value))] [$($permission.Name)] for user: [$aRef]"
                }
            }
            catch {          
                $ex = $PSItem
                if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
                    $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
                    $errorObj = Resolve-HTTPError -ErrorObject $ex
                    $errorMessage = "Error revoking StudyTubeV2 entitlement for team [($($permission.Value))] [$($permission.Name)] for user: [$aRef]. Error: $($errorObj.ErrorMessage)"
                }
                else {
                    $errorMessage = "Error revoking StudyTubeV2 entitlement for team [($($permission.Value))] [$($permission.Name)] for user: [$aRef]. Error: $($ex.Exception.Message)"
                }
                Write-Verbose $errorMessage
                $auditLogs.Add([PSCustomObject]@{
                        Action  = "RevokePermission"    
                        Message = $errorMessage
                        IsError = $true
                    })

            }
        }
        else {
            $newCurrentPermissions[$permission.Name] = $permission.Value
        }
    }

    # Handle case of empty defined dynamic permissions.  Without this the entitlement will error.
    if ($o -match "update|grant" -AND $subPermissions.count -eq 0) {
        $subPermissions.Add([PSCustomObject]@{
                DisplayName = "No Teams Defined"
                Reference   = [PSCustomObject]@{ Id = "No Teams Defined" }
            })
    }
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-HTTPError -ErrorObject $ex
        $errorMessage = "Error with StudyTubeV2 permissions. Error: $($errorObj.ErrorMessage)"
    }
    else {
        $errorMessage = "Error with StudyTubeV2 permissions. Error: $($ex.Exception.Message)"
    }
    Write-Verbose $errorMessage
}
#endregion Execute
finally { 
    # Check if auditLogs contains errors, if no errors are found, set success to true
    if (-NOT($auditLogs.IsError -contains $true)) {
        $success = $true
    }

    #region Build up result
    $result = [PSCustomObject]@{
        Success        = $success
        SubPermissions = $subPermissions
        AuditLogs      = $auditLogs
    }
    Write-Output ($result | ConvertTo-Json -Depth 10)
    #endregion Build up result
}