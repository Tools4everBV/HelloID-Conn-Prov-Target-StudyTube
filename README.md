
# HelloID-Conn-Prov-Target-StudyTube

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-StudyTube/refs/heads/main/Logo.png">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-StudyTube](#helloid-conn-prov-target-studytube)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Supported features](#supported-features)
  - [Getting started](#getting-started)
    - [HelloID Icon URL](#helloid-icon-url)
    - [Requirements](#requirements)
    - [Connection settings](#connection-settings)
    - [Correlation configuration](#correlation-configuration)
    - [Field mapping](#field-mapping)
    - [Account Reference](#account-reference)
  - [Remarks](#remarks)
    - [API rate limit](#api-rate-limit)
    - [Account correlation](#account-correlation)
    - [Pagination](#pagination)
    - [Permissions - Academy-Teams](#permissions---academy-teams)
        - [Team members](#team-members)
        - [Team managers](#team-managers)
        - [Importing permissions](#importing-permissions)
        - [Dynamic permissions](#dynamic-permissions)
        - [Creating teams](#creating-teams)
    - [`email_address` field must be unique](#email_address-field-must-be-unique)
    - [Custom fields](#custom-fields)
  - [Development resources](#development-resources)
    - [API endpoints](#api-endpoints)
    - [API documentation](#api-documentation)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-StudyTube_ is a _target_ connector. _StudyTube_ provides a set of REST API's that allow you to programmatically interact with its data. The HelloID connector uses the API endpoints listed in the table below.

| Endpoint                                | Description                      |
| --------------------------------------- | -------------------------------- |
| /api/v2/users                           | User related actions             |
| /api/v2/academy-teams                   | Team related actions             |
| /api/v2/academy-teams/{teamId}/users    | Team __member__ related actions  |
| /api/v2/academy-teams/{teamId}/managers | Team __manager__ related actions |
| /gateway/oauth/token                    | Authentication                   |

The API documentation can be found on: https://public-api.studytube.nl/api/v2/docs#/

## Supported features

The following features are available:

| Feature                                   | Supported | Actions                  | Remarks                                                                                               |
| ----------------------------------------- | --------- | ------------------------ | ----------------------------------------------------------------------------------------------------- |
| **Account Lifecycle**                     | ✅         | Create, Update, Delete   | Enable and disable are not available in the StudyTube API.                                            |
| **Permissions**                           | ✅         | Retrieve, Grant, Revoke  | Academy-team users and managers are supported (managers not dynamic).                                 |
| **Resources**                             | ✅         | Create, Retrieve, Update | Teams can be created and archived teams can be unarchived. Users are exported to CSV for correlation. |
| **Entitlement Import: Accounts**          | ✅         | Import                   |                                                                                                       |
| **Entitlement Import: Permissions**       | ✅         | Import                   | Team - users and Team - managers (no sub permission import script available)                          |
| **Governance Reconciliation Resolutions** | ✅         | -                        |                                                                                                       |

## Getting started

### HelloID Icon URL

```text
https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-StudyTube/refs/heads/main/Icon.png
```

### Requirements

- The HelloID on-premises agent must be installed.
- StudyTube API v2 access must be provisioned.
- A StudyTube ClientId and ClientSecret are required.
- The HelloID agent must be able to reach the configured StudyTube API and token URLs.

### Connection settings

The following settings are required to connect to the API.

| Setting                  | Description                                                                                                  | Mandatory |
| ------------------------ | ------------------------------------------------------------------------------------------------------------ | --------- |
| ClientId                 | The ClientId to connect to StudyTube.                                                                        | Yes       |
| ClientSecret             | The ClientSecret to connect to StudyTube.                                                                    | Yes       |
| BaseUrl                  | The URL to the StudyTube API.                                                                                | Yes       |
| TokenUrl                 | The URL to StudyTube for retrieving the access token.                                                        | Yes       |
| ResourcePageSize         | The number of records returned in a single request. The default value is `150`; the maximum value is `1000`. | Yes       |
| UserCsvExportFileAndPath | The file path where the user CSV export is saved.                                                            | Yes       |

### Correlation configuration

The correlation configuration is used to match an existing account within _StudyTube_ to a person in _HelloID_.

| Setting                   | Value                             |
| ------------------------- | --------------------------------- |
| Enable correlation        | `True`                            |
| Person correlation field  | `PersonContext.Person.ExternalId` |
| Account correlation field | `UID`                             |

> [!TIP]
> For more information, refer to the HelloID [correlation documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html).

### Field mapping

The field mapping can be imported by using the [fieldMapping.json](fieldMapping.json) file.

### Account Reference

The account reference is populated with the `id` property from the StudyTube user object.

## Remarks

> [!CAUTION]
> Version `2.0.0` of the connector introduces significant changes and is **no longer backwards compatible** with previous versions. This update requires the use of the new resource scripts for teams and users, and older configurations require adjustments to function correctly with the latest updates.

### API rate limit

The _StudyTube_ API has a throttle limit of __90__ requests per minute. To stay within this limit, every script waits `750` milliseconds after each API call.

> [!IMPORTANT]
> Configure the connector to run with a maximum of **one concurrent action**. Running multiple actions concurrently can exceed the StudyTube rate limit.

### Account correlation

The _StudyTube_ API does not allow users to be retrieved based on `employee_number` or `externalId`. They can only be retrieved using their `id`. The connector therefore uses [resources/Users/resources.ps1](resources/Users/resources.ps1) to export users to CSV. The _create_ lifecycle action uses this CSV to validate whether the user account exists.

### Pagination

The resource and import scripts require pagination. The default page size is `150`; the maximum value is `1000`.

> [!TIP]
> Configure the page size using the `ResourcePageSize` setting.

### Permissions - Academy-Teams

This connector supports separate permission sets for academy-team members and managers.

##### Team members

The scripts in `permissions/teams - users` manage team members using the `/api/v2/academy-teams/{teamId}/users` endpoint.

##### Team managers

The scripts in `permissions/teams - managers` manage team managers using the `/api/v2/academy-teams/{teamId}/managers` endpoint.

##### Importing permissions

Each permission folder contains an `import.ps1` script that imports teams together with their current members or managers. Because members and managers are retrieved per team, the import can take considerable time when many teams are present.

##### Dynamic permissions

If a property in the person contract is directly linked to an academy team in StudyTube, use the `subPermissions.ps1` script to assign permissions dynamically.

##### Creating teams

Use [resources/teams/resources.ps1](resources/teams/resources.ps1) to create teams within StudyTube. Archived teams are unarchived when applicable.

### `email_address` field must be unique

Creating a new user with an email address that already exists will update the existing user instead of adding a new one. The _create_ lifecycle action validates email uniqueness and returns an error when the email is already in use.

### Custom fields

See the [custom fields documentation](READMEcustomField.md).

## Development resources

### API endpoints

The following endpoints are used by the connector:

| Endpoint                                  | HTTP method       | Description                             |
| ----------------------------------------- | ----------------- | --------------------------------------- |
| `/api/v2/users`                           | GET, POST, PUT    | Retrieve, create and update users.      |
| `/api/v2/academy-teams`                   | GET, POST         | Retrieve and create academy-teams.      |
| `/api/v2/academy-teams/{teamId}/users`    | GET, POST, DELETE | Retrieve, add and remove team members.  |
| `/api/v2/academy-teams/{teamId}/managers` | GET, POST, DELETE | Retrieve, add and remove team managers. |
| `/gateway/oauth/token`                    | POST              | Retrieve an access token.               |

### API documentation

The official StudyTube API documentation is available at:

https://public-api.studytube.nl/api/v2/docs#/

## Getting help

> [!TIP]
> For more information on configuring a HelloID PowerShell connector, refer to the [HelloID documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html).

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
