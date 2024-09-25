######################################################
# HelloID-Conn-Prov-Target-StudyTube-Permissions
# PowerShell V2
######################################################

try {
    Write-Information 'Retrieving all active academy-teams from StudyTube'
    $teamResult = Import-Csv -Path $($actionContext.Configuration.TeamsCsvExportFileAndPath) -Encoding UTF8
    foreach ($team in $teamResult) {
        $outputContext.Permissions.Add( @{
                DisplayName    = $team.name
                Identification = @{
                    DisplayName = $team.name
                    Reference   = $team.id
                }
            }
        )
    }
} catch {
    $ex = $PSItem
    Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
}
