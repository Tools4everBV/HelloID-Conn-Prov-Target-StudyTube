#####################################################
# HelloID-Conn-Prov-Target-StudyTubeV2-Entitlement-DynamicPermission
#
# Version: 1.1.0
#####################################################

$currentPermissions = @{}
foreach ($permission in $actionContext.CurrentPermissions) {
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
        client_id     = $($actionContext.Configuration.ClientId)
        client_secret = $($actionContext.Configuration.ClientSecret)
        grant_type    = 'client_credentials'
        scope         = 'read write'
    }
    $tokenResponse = Invoke-RestMethod -Uri "$($actionContext.Configuration.TokenUrl)/gateway/oauth/token" -Method 'POST' -Headers $headers -Body $tokenBody -verbose:$false

    Write-Verbose 'Setting authorization header'
    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add("Authorization", "Bearer $($tokenResponse.access_token)")

    Write-Verbose 'Retrieving all active academy-teams from StudyTube'
    $splatGetUserParams = @{
        Uri         = "$($actionContext.Configuration.BaseUrl)/api/v2/academy-teams/active"
        Method      = 'GET'
        Headers     = $headers
        ContentType = 'application/json'
    }
    $teamResult = Invoke-RestMethod @splatGetUserParams
    # Make Name the grouped value to search with the correlationValue
    $teamLookup = $teamResult | Group-Object -Property Name -AsHashTable -AsString

    # #region Change mapping here
    $desiredPermissions = @{}
    if ($actionContext.Operation -ne "revoke") {
        # Example: Contract Based Logic:
        foreach ($contract in $personContext.Person.Contracts) {
            Write-Verbose ("Contract in condition: {0}" -f $contract.Context.InConditions)
            if ($contract.Context.InConditions -eq $true -OR ($actionContext.DryRun -eq $True)) {

                # Example of correlation value. Change this value to your needs
                $correlationValue = $contract.Title.Name

                # Search the team name with the correlationValue
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

    Write-Information ("Existing Permissions: {0}" -f ($actionContext.CurrentPermissions.DisplayName | ConvertTo-Json))
    #endregion Change mapping here

    #region Execute
    # Compare desired with current permissions and grant permissions
    foreach ($permission in $desiredPermissions.GetEnumerator()) {
        $outputContext.SubPermissions.Add([PSCustomObject]@{
                DisplayName = $permission.Value
                Reference   = [PSCustomObject]@{ Id = $permission.Name }
            })

        if (-Not $currentPermissions.ContainsKey($permission.Name)) {
            try {
                if (-not($actionContext.DryRun -eq $true)) {
                    Write-Verbose "Granting StudyTubeV2 entitlement: [($($permission.Value))] [$($permission.Name)] for user: [$($actionContext.References.Account)]"

                    $splatGrantPermissionParams = @{
                        Uri         = "$($actionContext.Configuration.BaseUrl)/api/v2/academy-teams/$($permission.Key)/users"
                        Method      = 'POST'
                        Headers     = $headers
                        ContentType = 'application/x-www-form-urlencoded'
                        Body        = @{
                            user_id = $actionContext.References.Account
                        }
                    }
                    $grantPermissionsResponse = Invoke-RestMethod @splatGrantPermissionParams -verbose:$false
                    if ($grantPermissionsResponse) {
                        $outputContext.AuditLogs.Add([PSCustomObject]@{
                                Action  = "GrantPermission"
                                Message = "Successfully granted StudyTubeV2 entitlement for team [($($permission.Value))] [$($permission.Name)] for user: [$($actionContext.References.Account)]"
                                IsError = $false
                            })
                    }
                }
                else {
                    Write-Warning "DryRun: Would grant permission to team [($($permission.Value))] [$($permission.Name)] for user: [$($actionContext.References.Account)]"
                }
            }
            catch {
                $ex = $PSItem
                if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
                    $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
                    $errorObj = Resolve-HTTPError -ErrorObject $ex
                    $errorMessage = "Error granting StudyTubeV2 entitlement for team [($($permission.Value))] [$($permission.Name)] for user: [$($actionContext.References.Account)]. Error: $($errorObj.ErrorMessage)"
                }
                else {
                    $errorMessage = "Error granting StudyTubeV2 entitlement for team [($($permission.Value))] [$($permission.Name)] for user: [$($actionContext.References.Account)]. Error: $($ex.Exception.Message)"
                }
                Write-Verbose $errorMessage
                $outputContext.AuditLogs.Add([PSCustomObject]@{
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
            try {
                if (-not($actionContext.DryRun -eq $true)) {
                    Write-Verbose "Revoking StudyTubeV2 entitlement: [($($permission.Value))] [$($permission.Name)] for user: [$($actionContext.References.Account)]"

                    $splatRevokePermissionParams = @{
                        Uri         = "$($actionContext.Configuration.BaseUrl)/api/v2/academy-teams/$($permission.Key)/users"
                        Method      = 'DELETE'
                        Headers     = $headers
                        ContentType = 'application/x-www-form-urlencoded'
                        Body        = @{
                            user_id = $actionContext.References.Account
                        }
                    }
                    try {
                        $null = Invoke-RestMethod @splatRevokePermissionParams -StatusCodeVariable statusCode -verbose:$false
                        if ($statusCode -eq 204) {
                            $outputContext.AuditLogs.Add([PSCustomObject]@{
                                    Action  = "RevokePermission"
                                    Message = "Successfully revoked StudyTubeV2 entitlement for team [($($permission.Value))] [$($permission.Name)] for user: [$($actionContext.References.Account)]"
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
                            $outputContext.AuditLogs.Add([PSCustomObject]@{
                                    Action  = "RevokePermission"
                                    Message = "Successfully revoked StudyTubeV2 entitlement for team [($($permission.Value))] [$($permission.Name)] for user: [$($actionContext.References.Account)] (already removed)"
                                    IsError = $false
                                })
                        }
                        else {
                            throw
                        }
                    }
                }
                else {
                    Write-Warning "DryRun: Would revoke permission from team [($($permission.Value))] [$($permission.Name)] for user: [$($actionContext.References.Account)]"
                }
            }
            catch {
                $ex = $PSItem
                if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
                    $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
                    $errorObj = Resolve-HTTPError -ErrorObject $ex
                    $errorMessage = "Error revoking StudyTubeV2 entitlement for team [($($permission.Value))] [$($permission.Name)] for user: [$($actionContext.References.Account)]. Error: $($errorObj.ErrorMessage)"
                }
                else {
                    $errorMessage = "Error revoking StudyTubeV2 entitlement for team [($($permission.Value))] [$($permission.Name)] for user: [$($actionContext.References.Account)]. Error: $($ex.Exception.Message)"
                }
                Write-Verbose $errorMessage
                $outputContext.AuditLogs.Add([PSCustomObject]@{
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
        $outputContext.SubPermissions.Add([PSCustomObject]@{
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
        $outputContext.Success = $true
    }
}
