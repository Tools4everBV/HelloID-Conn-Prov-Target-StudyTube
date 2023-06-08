# HelloID-Conn-Prov-Target-StudyTubeV2


| :information_source: Information |
|:---------------------------|
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |
<br />

<p align="center"> 
  <img src="https://www.github.com/test.png">
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

_HelloID-Conn-Prov-Target-StudyTubeV2_ is a _target_ connector. StudyTube provides a set of REST API's that allow you to programmatically interact with it's data. The HelloID connector uses the API endpoints listed in the table below.

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
| CLientId     | The CLientId to connect to StudyTube | Yes        |
| ClientSecret | The ClientSecret to connect to StudyTube  | Yes        |
| BaseUrl      | The URL to the StudyTube API.| Yes        |
| TokenUrl     | The URL to StudyTube for retrieving the accessToken. | Yes        |
| IsDebug      | When toggled, debug logging will be displayed | No         |

### Prerequisites

### Remarks

#### Creation / correlation process

Normally, the connector will verify if an account must be either created or -if an existing account is found- correlated. A new functionality is the possibility to update the account in the target system during the correlation process. Default this behavior is disabled. Meaning, the account will only be created or correlated.

You can change this behaviour in the `create.ps1` by setting the following boolean value to true: `$updatePerson = $true`. You will find this boolean value on line 55.

#### Correlation

The `create.ps1` either creates or correlates a HelloID person with a StudyTube account. Correlation is done using a specific ID that is unique within StudyTube. A Student account can only be retrieved/updated/deleted using this ID.

> StudyTube accounts and teams are retrieved using pagination

## Setup the connector

- On the connector confiuration `General` tab, make sure that the `Execute on-premises` switch is toggled off.

## Getting help

> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012558020-Configure-a-custom-PowerShell-target-system) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
