
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
      - [Account correlation](#account-correlation)
      - [Pagination](#pagination)
      - [Permissions - Academy-Teams](#permissions---academy-teams)
        - [Dynamic permissions](#dynamic-permissions)
        - [Retrieve teams](#retrieve-teams)
        - [Creating teams](#creating-teams)
      - [`email_address` field must be unique](#email_address-field-must-be-unique)
      - [Custom fields](#custom-fields)
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

| Action                                  | Description                                |
| --------------------------------------- | ------------------------------------------ |
| create.ps1                              | PowerShell _create_ lifecycle action       |
| delete.ps1                              | PowerShell _delete_ lifecycle action       |
| update.ps1                              | PowerShell _update_ lifecycle action       |
| \permissions\teams\grantPermission.ps1  | PowerShell _grant_ lifecycle action        |
| \permissions\teams\revokePermission.ps1 | PowerShell _revoke_ lifecycle action       |
| \permissions\teams\subPermissions.ps1   | PowerShell _All-in-one_ lifecycle action   |
| \permissions\teams\permissions.ps1      | PowerShell _permissions_ lifecycle action  |
| configuration.json                      | Default _configuration.json_               |
| fieldMapping.json                       | Default _fieldMapping.json_                |
| \resources\teams\create\resources.ps1   | Creates teams within StudyTube             |
| \resources\teams\retrieve\resources.ps1 | Exports all __active__ teams to a CSV file |
| \resources\user\resources.ps1           | Exports all users to a CSV file            |

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

| Setting                   | Description                                                                                                                                              | Mandatory |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- | --------- |
| ClientId                  | The ClientId to connect to StudyTube.                                                                                                                    | Yes       |
| ClientSecret              | The ClientSecret to connect to StudyTube.                                                                                                                | Yes       |
| BaseUrl                   | The URL to the StudyTube API.                                                                                                                            | Yes       |
| TokenUrl                  | The URL to StudyTube for retrieving the accessToken.                                                                                                     | Yes       |
| ResourcePageSize          | The number of records returned in a single request. The default value is `150`. Can be increased when facing issues related to making too many requests. | Yes       |
| UsersCsvExportFileAndPath | Specifies the name and file path where the CSV teams export will be saved.                                                                               | Yes       |
| TeamsCsvExportFileAndPath | Specifies the name and file path where the CSV users export will be saved.                                                                               | Yes       |

### Pre-Requisites

- [ ] The HelloID on-premises agent must be installed.

### Remarks

> [!CAUTION]
> Version `2.0.0` of the connector introduces significant changes and is **no longer backwards compatible** with previous versions. This update requires the use of the new resource scripts for teams and users, and older configurations require adjustments to function correctly with the latest updates.

#### Account correlation

The _StudyTube_ API does not allow users to be retrieved based on `employee_number` or `externalId`. They can only be retrieved using their `id`. The only workaround is to retrieve __all users__ within the _create_ lifecyle action. However, since this is not considered a best practice and because _StudyTube_ itself has an API throttle limit of __90__ requests per minute, the connector uses a _resources_ script to retrieve all users and export them to a CSV file. Within the _create_ lifecycle action, this CSV is used to validate whether the user account exists.

#### Pagination

The resource scripts to retrieve users and teams require pagination. The default page size is set to: `150`. If you encounter problems with to many request, try a higher value, for example: `200`, the maximum value is: `1000`.

> [!TIP]
> You can configure the pagesize for both resource scripts using the configuration setting: _ResourcePageSize_.

#### Permissions - Academy-Teams

This connector allows for the assignment of academy-teams through separate _grant/revoke/permissions_ lifecycle actions.

##### Dynamic permissions

If a property in the person contract is directly linked to an academy team in StudyTube, you can use the `_subPermissions_` script to assign permissions dynamically.

##### Retrieve teams

Because retrieving teams could result in too many requests being made, a separate resource script is provided to retrieve all teams and export them to a CSV.

If you use the `_subPermissions_` script, this CSV file will be searched to look up the team name and ensure it matches a property from the person contract.
If you're using the separate grant/revoke scripts and still encounter the "too many requests" issue, you might also need the `_/resources/teams/retrieve/resources.ps1_` to retrieve teams. In that case, the `_permissions_` script will need to be modified to import teams from the CSV file.

##### Creating teams

If a property in the person contract is directly linked to an academy team in StudyTube, you can use the `_/resources/teams/create/resources.ps1_` script to create teams within StudyTube. Additionally, archived teams will be unarchived.

#### `email_address` field must be unique

Creating a new user with an email address that already exists will update the existing user instead of adding a new one. To avoid this issue, a validation step has been implemented to confirm the uniqueness of the email address. If the email is not unique, the _create_ lifecycle action will return an error.

#### Custom fields
[Custom fields readme](https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-StudyTube/blob/main/READMEcustomField.md)

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

> [!TIP]
>  _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
