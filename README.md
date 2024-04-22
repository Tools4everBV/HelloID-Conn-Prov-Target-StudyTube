
# HelloID-Conn-Prov-Target-StudyTube

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

> [!WARNING]
> This connector has not been tested on a _StudyTube_ environment. Therefore, changes will have to be made accordingly.

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
    - [Remarks](#remarks)
      - [All users will be retrieved within the `create` lifecycle](#all-users-will-be-retrieved-within-the-create-lifecycle)
      - [PageSize](#pagesize)
      - [Multiple accounts](#multiple-accounts)
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
    | Account correlation field | `uuid`                            |

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

#### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

### Connection settings

The following settings are required to connect to the API.

| Setting      | Description                                                                                    | Mandatory |
| ------------ | ---------------------------------------------------------------------------------------------- | --------- |
| ClientId     | The ClientId to connect to StudyTube                                                           | Yes       |
| ClientSecret | The ClientSecret to connect to StudyTube                                                       | Yes       |
| BaseUrl      | The URL to the StudyTube API.                                                                  | Yes       |
| TokenUrl     | The URL to StudyTube for retrieving the accessToken.                                           | Yes       |
| PageSize     | Default 25. If you encounter problems with to many request try a higher value, for example 200 | Yes       |

### Remarks

#### All users will be retrieved within the `create` lifecycle

The _StudyTube_ API does not provide the option to fetch a user based on its `uuid`; instead, users can only be retrieved using their `id`. Within the _create_ lifecycle action, all users are fetched. Additionally, we have the functionality to group and filter users based on the `uuid` as needed.

#### PageSize

Because __all__ users are retrieved, paging is also required. You can change the `PageSize` in the configuration. The default `PageSize` is set to __25__. If you encounter problems with to many request try a higher value, for example __200__.

#### Multiple accounts

During the retrieval of all accounts from _StudyTube_, there are instances where the response may include duplicate objects. In such scenarios, the create lifecycle action raises an error rather than proceeding.

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

> [!TIP]
>  _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/

