# HelloID-Conn-Prov-Target-StudyTube


| :information_source: Information |
|:---------------------------|
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.       |
<br />
<p align="center">
  <img src="https://www.tools4ever.nl/connector-logos/studytube-logo.png">
</p>

## Table of contents

- [Introduction](#Introduction)
- [Getting started](#Getting-started)
  + [Connection settings](#Connection-settings)
  + [Prerequisites](#Prerequisites)
  + [Remarks](#Remarks)
- [Setup the connector](@Setup-The-Connector)
- [Getting help](#Getting-help)
- [HelloID Docs](#HelloID-docs)

## Introduction

_HelloID-Conn-Prov-Target-StudyTube_ is a _target_ connector. StudyTube provides a set of REST API's that allow you to programmatically interact with it's data. The HelloID connector uses the API endpoints listed in the table below.

| Endpoint     | Description |
| ------------ | ----------- |
| /Users       | Create/Update/Delete users |
| /Teams       | Manage team permissions |

## Getting started

> This connector is created for PowerShell Core only and therefore cannot be used in conjunction with the HelloID On-Premises agent using Windows PowerShell.

### Connection settings

The following settings are required to connect to the API.

| Setting      | Description                        | Mandatory   |
| ------------ | -----------                        | ----------- |
| ApiToken     | The API Token used to authenticate against StudyTube This must be retrieved from within the application  | Yes        |
| CompanyId    | The CompanyID used to authenticate against StudyTube This must be retrieved from within the application | Yes         |
| BaseUrl      | The URL to the StudyTube application | Yes         |

### Prerequisites

### Remarks

#### Correlation

The `create.ps1` either creates or correlates a HelloID person with a StudyTube account. Correlation is done using a specific ID that is unique within StudyTube. A Student account can only be retrieved/updated/deleted using this ID. The account object returned from Studytube howvever, does contain the `employee number`.

In order to get the ID:

- All users from StudyTube are retrieved.
- A lookup table is created based on the `employee number` property.
- The StudyTube account (and unique ID) will be searched using the `employee number`.

> StudyTube accounts are retrieved using pagination

> Because all StudyTube accounts are retrieved within the `create.ps1` you may encounter issue's.

#### Entitlements

A `team` within StudyTube can either have members or managers. Currently the entitlements only manages the member permissions for a team.

## Setup the connector

- On the connector confiuration `General` tab, make sure that the `Execute on-premises` switch is toggled off.

## Getting help

> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012558020-Configure-a-custom-PowerShell-target-system) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
