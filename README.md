
# HelloID-Conn-Prov-Target-StudyTube

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="https://www.tools4ever.nl/connector-logos/studytube-logo-2.png">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-StudyTube](#helloid-conn-prov-target-studytube)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Getting started](#getting-started)
    - [Provisioning PowerShell V2 connector](#provisioning-powershell-v2-connector)
      - [Correlation configuration](#correlation-configuration)
      - [Field mapping](#field-mapping)
    - [Connection settings](#connection-settings)
    - [Pre-Requisites](#pre-requisites)
    - [Remarks](#remarks)
      - [All users will be retrieved within the `create` lifecycle](#all-users-will-be-retrieved-within-the-create-lifecycle)
      - [CsvExportFileAndPath](#csvexportfileandpath)
      - [Correlation](#correlation)
      - [ResourcePageSize](#resourcepagesize)
      - [Permissions](#permissions)
      - [Uniqueness](#uniqueness)
      - [CustomField](#customfield)
      - [Encoding](#encoding)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-StudyTube_ is a _target_ connector. _StudyTube_ provides a set of REST API's that allow you to programmatically interact with its data. The HelloID connector uses the API endpoints listed in the table below.

| Endpoint              | Description                |
| --------------------- | -------------------------- |
| /api/v2/users         | User related actions       |
| /api/v2/academy-teams | Permission related actions |
| /gateway/oauth/token  | Authentication             |

The API documentation can be found on: https://public-api.studytube.nl/api/v2/docs#/

The following lifecycle actions are available:

| Action               | Description                               |
| -------------------- | ----------------------------------------- |
| create.ps1           | PowerShell _create_ lifecycle action      |
| delete.ps1           | PowerShell _delete_ lifecycle action      |
| update.ps1           | PowerShell _update_ lifecycle action      |
| grantPermission.ps1  | PowerShell _grant_ lifecycle action       |
| revokePermission.ps1 | PowerShell _revoke_ lifecycle action      |
| subPermissions.ps1   | PowerShell _All-in-one_ lifecycle action  |
| permissions.ps1      | PowerShell _permissions_ lifecycle action |
| configuration.json   | Default _configuration.json_              |
| fieldMapping.json    | Default _fieldMapping.json_               |

## Getting started

### Provisioning PowerShell V2 connector

#### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _StudyTube_ to a person in _HelloID_.

To properly setup the correlation:

1. Open the `Correlation` tab.

2. Specify the following configuration:

    | Setting                   | Value                             |
    | ------------------------- | --------------------------------- |
    | Enable correlation        | `True`                            |
    | Person correlation field  | `PersonContext.Person.ExternalId` |
    | Account correlation field | `UID`                             |

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

#### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

### Connection settings

The following settings are required to connect to the API.

| Setting              | Description                                                                                     | Mandatory |
| -------------------- | ----------------------------------------------------------------------------------------------- | --------- |
| ClientId             | The ClientId to connect to StudyTube                                                            | Yes       |
| ClientSecret         | The ClientSecret to connect to StudyTube                                                        | Yes       |
| BaseUrl              | The URL to the StudyTube API.                                                                   | Yes       |
| TokenUrl             | The URL to StudyTube for retrieving the accessToken.                                            | Yes       |
| ResourcePageSize     | Default 150. If you encounter problems with to many request try a higher value, for example 200 | Yes       |
| CsvExportFileAndPath | Specifies the name and file path where the CSV User export will be saved                        | Yes       |

### Pre-Requisites

- An on-premises agent.
- Storage available to save the user export file, with direct access by the agent.
- All Connection settings properties.


### Remarks

#### All users will be retrieved within the `create` lifecycle

The _StudyTube_ API does not provide the option to fetch a user based on `UID` (EmployeeNumber); instead, users can only be retrieved using their `id`. Therefore, when you have a large number of employees, you cannot fetch the users in the create lifecycle without reaching the API throttling limit of StudyTube. Which is at moment of writing 90 call per minute.


#### CsvExportFileAndPath

The connector is designed for larger companies, so it does not retrieve users during the creation lifecycle. Instead, a Resource script is used to retrieve all users and store them in a CSV file on disk. This requires storage accessible by the agent. The location can be defined in the configuration item named `CsvExportFileAndPath`.

#### Correlation
The creation process performs its correlation not against the StudyTube API, but against the CSV file generated by the Resource script.

If you have a small company and want to use the connector, please consider using a direct API call to perform the correlation. This can be done with a code change like the example below.

``` Powershell
Write-Information 'Retrieving authorization token'
$headers = [System.Collections.Generic.Dictionary[string, string]]::new()
$headers.Add("Content-Type", "application/x-www-form-urlencoded")
$tokenBody = @{
    client_id     = $($actionContext.Configuration.ClientId)
    client_secret = $($actionContext.Configuration.ClientSecret)
    grant_type    = 'client_credentials'
    scope         = 'read write'
}
$tokenResponse = Invoke-RestMethod -Uri "$($actionContext.Configuration.TokenUrl)/gateway/oauth/token" -Method 'POST' -Headers $headers -Body $tokenBody -verbose:$false

Write-Information 'Setting authorization header'
$headers = [System.Collections.Generic.Dictionary[string, string]]::new()
$headers.Add("Authorization", "Bearer $($tokenResponse.access_token)")

$splatGetUserParams = @{
    Uri         = "$($actionContext.Configuration.BaseUrl)/api/v2/users"
    Method      = 'GET'
    Headers     = $headers
}
$userResult = Invoke-RestMethod @splatGetUserParams -Verbose:$false

$userListSorted = $userResult | Sort-Object -Property id -Unique
$lookupUser = $userListSorted | Group-Object -Property uid -AsHashTable -AsString
$correlatedAccount = $lookupUser[$($correlationValue)]
```

> [!TIP]
> The Tools4ever Connector team contacted the supplier with a query to add a filter to the user endpoint to retrieve users by `UID`. If this request is implemented, the connector will be able to directly query the API during the correlation process and eliminate the need for the Resource script.

#### ResourcePageSize

Because __all__ users are retrieved, paging is also required. You can change the `ResourcePageSize` in the configuration. The default `ResourcePageSize` is set to __150__. If you encounter problems with to many request try a higher value, for example __200__, the max is __1000__

#### Permissions
There are two types of permissions added in the repository, and you can choose one. Alternatively, you can use the all-in-one script subPermissions.ps1, or the grantPermission and revokePermission scripts. The preferred solution is to use the individual scripts. However, when you reach the maximum number of business rules, consider using subPermissions.

#### Uniqueness
- The property `employee_number` is not unique in StudyTube, which means that the `UID` should be used as the correlation key.
- The email address should be unique in StudyTube. When the email address already exists, attempting to create a new user with an existing email address results in updating the existing user instead of creating a new one. A condition has been added to the creation process to avoid this update and stop when this situation occurs.


#### CustomField
The StudyTube API supports the use of custom fields. The current code does not implement custom fields, but you can find examples of how to implement them in the [ReadmeCustomField.md](https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-StudyTube/blob/main/READMEcustomField.md) file.

> [!TIP]
The connector does not support adding mew custom fields without any code changes. All new customFields requires code changes!

#### Encoding
In HelloID, the connector encountered encoding issues. You might need to add the following lines to the update script, directly below the `Get user <id`> web request, to retrieve diacritics with the correct encoding.

```powerShell
$correlatedAccount = Invoke-RestMethod @splatGetUserParams -Verbose:$false
$isoEncoding = [System.Text.Encoding]::GetEncoding('ISO-8859-1')
$correlatedAccount = [System.Text.Encoding]::UTF8.GetString($isoEncoding.GetBytes(($correlatedAccount | ConvertTo-Json -Depth 10))) | ConvertFRom-json

$outputContext.PreviousData = $correlatedAccount
```



## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

> [!TIP]
>  _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/

