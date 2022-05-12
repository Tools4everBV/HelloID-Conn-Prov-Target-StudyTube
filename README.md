# HelloID-Conn-Prov-Target-StudyTubeV2

| :warning: Warning |
|:---------------------------|
| Note that this connector is "a work in progress" and therefore not ready to use in your production environment. |

| :information_source: Information |
|:---------------------------|
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |

<p align="center">
  <img src="https://www.studytube.nl/hubfs/raw_assets/public/DiamondTube/assets/images/logo/logo-dark-blue.svg" width='400'>
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
| BaseUrl      | The URL to the StudyTube application | Yes         |

### Prerequisites

### Remarks

#### Correlation

The `create.ps1` either creates or correlates a HelloID person with a StudyTube account. Correlation is done using a specific ID that is unique within StudyTube. A Student account can only be retrieved/updated/deleted using this ID. The account object returned from Studytube howvever, does contain the `employee number`.

> StudyTube accounts and teams are retrieved using pagination

## Setup the connector

- On the connector confiuration `General` tab, make sure that the `Execute on-premises` switch is toggled off.

## Getting help

> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012558020-Configure-a-custom-PowerShell-target-system) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
