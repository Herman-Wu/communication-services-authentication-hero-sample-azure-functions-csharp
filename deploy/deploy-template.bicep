// This is the deployment environmentName name, if want to add more potential environmentName, please edit allowed section
@allowed([
  'dev'
  'stg'
  'prod'
])
param environmentName string

// This is the system name or solution name you prefer to use to indicate this deployment's content
// Please using alphabet / alphanumerics, no special characters
@maxLength(10)
param deploymentName string = 'acs-sample'

// This is a version string, it indicates the version of this deployment
@maxLength(4)
param version string


@minValue(7)
@maxValue(90)
param kvRetentionDays int = 90

param location string = resourceGroup().location

var sharedVars = json(loadTextContent('./shared_vars.json'))

param resourceTags object = {
  Environment: environmentName
  Project: 'Adv-ACS-Auth-Hero-Sample'
  CreatedBy: 'IaC'
  Version: version
}

@description('Specifies the OS used for the Azure Function hosting plan.')
@allowed([
  'Windows'
  'Linux'
])
param functionPlanOS string = 'Linux'

@description('The built-in runtime stack to be used for a Linux-based Azure Function. This value is ignore if a Windows-based Azure Function hosting plan is used. Get the full list by executing the "az webapp list-runtimes --linux" command.')
@allowed([
  'dotnet|3.1'
  'dotnet|6'
])
param linuxRuntime string = 'dotnet|6'

// The term "reserved" is used by ARM to indicate if the hosting plan is a Linux or Windows-based plan.
// A value of true indicated Linux, while a value of false indicates Windows.
// See https://docs.microsoft.com/en-us/azure/templates/microsoft.web/serverfarms?tabs=json#appserviceplanproperties-object.
var isReserved = (functionPlanOS == 'Linux') ? true : false


param storageAccountConfig object = {
  sku :{
    name: 'Standard_LRS'
  }
}
param acsConfig object = {
  properties: {
    dataLocation: 'United States' // Please check ACS Data Residency for more information. https://docs.microsoft.com/en-us/azure/communication-services/concepts/privacy#data-residency
  }
}

param devFunctionPlan object = {
  sku: {
    name: 'B1'
    tier: 'Basic'
    size: 'B1'
    family: 'B'
    capacity: 1
  }
  kind: 'linux'
}
param stgFunctionPlan object = {
  sku: {
    name: 'B1'
    tier: 'Basic'
    size: 'B1'
    family: 'B'
    capacity: 1
  }
  kind: 'linux'
}
param prodFunctionPlan object = {
  sku: {
    name: 'B1'
    tier: 'Basic'
    size: 'B1'
    family: 'B'
    capacity: 1
  }
  kind: 'linux'
}

var environmentConfigMap = {
  prod: {
    storageAccount: {
      sku: storageAccountConfig.sku
    }
    acs: {
      dataLocation: acsConfig.properties.dataLocation
    }
    funcplan: {
      sku: prodFunctionPlan.sku
      kind: prodFunctionPlan.kind
    }  
    function: {
      httpsOnly: true
    }     
  }
  stg: {
    storageAccount: {
      sku: storageAccountConfig.sku
    }
    acs: {
      dataLocation: acsConfig.properties.dataLocation
    }
    funcplan: {
      sku: stgFunctionPlan.sku
      kind: stgFunctionPlan.kind
    }  
    function: {
      httpsOnly: false
    }
  }
  dev: {
    storageAccount: {
      sku: storageAccountConfig.sku
    }
    acs: {
      dataLocation: acsConfig.properties.dataLocation
    }
    funcplan: {
      sku: devFunctionPlan.sku
      kind: devFunctionPlan.kind
    }
    function: {
      httpsOnly: false
    }     
  }
}

var storageName = take(deploymentName, sharedVars.storageAccountMaxLength - length('${sharedVars.storageAccountPrefix}${environmentName}${version}'))
// Storage account for the queues and tables
resource storage 'Microsoft.Storage/storageAccounts@2021-06-01' = {
  name: toLower('${sharedVars.storageAccountPrefix}${storageName}${environmentName}${version}')
  location: location
  tags: resourceTags
  kind: 'StorageV2'
  sku: environmentConfigMap[environmentName].storageAccount.sku
  properties: {
    isHnsEnabled: false
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
  }
}

var communicationServiceName = take(deploymentName, sharedVars.communicationServiceMaxLength - length('${sharedVars.communicationServicePrefix}--${environmentName}-${version}'))
resource acs 'Microsoft.Communication/communicationServices@2020-08-20' = {
  name: toLower('${sharedVars.communicationServicePrefix}-${communicationServiceName}-${environmentName}-${version}')
  location: 'global'
  tags: resourceTags
  properties: {
    dataLocation: environmentConfigMap[environmentName].acs.dataLocation
  }
}

var storageAccessKey = listKeys(storage.id, storage.apiVersion).keys[0].value
var composedStorageConnectionString = 'DefaultEndpointsProtocol=https;AccountName=${storage.name};AccountKey=${storageAccessKey};EndpointSuffix=core.windows.net'

var keyVaultName = take(deploymentName, sharedVars.keyVaultMaxLength - length('${sharedVars.keyVaultPrefix}--${environmentName}-${version}'))
resource keyvault 'Microsoft.KeyVault/vaults@2021-06-01-preview' = {
  name: toLower('${sharedVars.keyVaultPrefix}-${keyVaultName}-${environmentName}-${version}')
  location: location
  tags: resourceTags
  properties: {
    enabledForDeployment: true
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: true
    tenantId: subscription().tenantId
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: azureFunction.identity.principalId
        permissions: {
          secrets: [
            'list'
            'get'
          ]
        }
      }
    ]
    sku: {
      name: 'standard'
      family: 'A'
    }
    enablePurgeProtection: true
    enableSoftDelete: true
    softDeleteRetentionInDays: kvRetentionDays
  }

  resource acsPrimaryKey 'secrets' = {
    name: 'acsPrimaryKey'
    tags: resourceTags
    properties: {
      value: listKeys(acs.id, acs.apiVersion).primaryKey
      attributes: {
        enabled: true
        exp: sharedVars.keyVaultSecretExp
      }
    }
  }
  resource acsPrimaryConnectionString 'secrets' = {
    name: 'acsPrimaryConnectionString'
    tags: resourceTags
    properties: {
      value: listKeys(acs.id, acs.apiVersion).primaryConnectionString
      attributes: {
        enabled: true
        exp: sharedVars.keyVaultSecretExp
      }
    }
  }

  resource storageConnectionString 'secrets' = {
    name: 'storageConnectionString'
    tags: resourceTags
    properties: {
      value: composedStorageConnectionString
      attributes: {
        enabled: true
        exp: sharedVars.keyVaultSecretExp
      }
    }
  }

  resource azureAdPrimaryTenantId 'secrets' = {
    name: 'azureAdPrimaryTenantId'
    tags: resourceTags
    properties: {
      value: 'temp value, should be manually replaced after tenant creation process'
      attributes: {
        enabled: true
        exp: sharedVars.keyVaultSecretExp
      }
    }
  }
  resource azureAdWebapiClientId 'secrets' = {
    name: 'azureAdWebapiClientId'
    tags: resourceTags
    properties: {
      value: 'temp value, should be manually replaced after webapi app registration process'
      attributes: {
        enabled: true
        exp: sharedVars.keyVaultSecretExp
      }
    }
  }
  resource azureAdWebapiClientSecret 'secrets' = {
    name: 'azureAdWebapiClientSecret'
    tags: resourceTags
    properties: {
      value: 'temp value, should be manually replaced after webapi app registration process'
      attributes: {
        enabled: true
        exp: sharedVars.keyVaultSecretExp
      }
    }
  }
  resource azureAdPrimaryDomain 'secrets' = {
    name: 'azureAdPrimaryDomain'
    tags: resourceTags
    properties: {
      value: 'temp value, should be manually replaced after tenant creation process'
      attributes: {
        enabled: true
        exp: sharedVars.keyVaultSecretExp
      }
    }
  }
}

var funcPlanName = take(deploymentName, sharedVars.funcPlanMaxLength - length('-${sharedVars.funcPlanPrefix}-${environmentName}-${version}'))
resource azureFunctionPlan 'Microsoft.Web/serverfarms@2021-02-01' = {
  name: toLower('${sharedVars.funcPlanPrefix}-${funcPlanName}-${environmentName}-${version}')
  location: location
  tags: resourceTags
  kind: environmentConfigMap[environmentName].funcplan.kind
  sku: environmentConfigMap[environmentName].funcplan.sku
  properties: {
    perSiteScaling: false
    elasticScaleEnabled: false
    maximumElasticWorkerCount: 1
    isSpot: false
    reserved: isReserved    
    isXenon: false
    hyperV: false
    targetWorkerCount: 0
    targetWorkerSizeId: 0
    zoneRedundant: false
  }
}

var keyvaultReferenceName = toLower('${sharedVars.keyVaultPrefix}-${keyVaultName}-${environmentName}-${version}')
var functionName = take(deploymentName, sharedVars.functionMaxLength - length('-${sharedVars.functionPrefix}-${environmentName}-${version}'))
resource azureFunction 'Microsoft.Web/sites@2021-02-01' = {
  name: toLower('${sharedVars.functionPrefix}-${functionName}-${environmentName}-${version}')
  location: location
  tags: resourceTags
  kind: isReserved ? 'functionapp,linux' : 'functionapp'
  properties: {
    serverFarmId: azureFunctionPlan.id
    reserved: isReserved    
    httpsOnly: environmentConfigMap[environmentName].function.httpsOnly
    siteConfig: {
      vnetRouteAllEnabled: true
      functionsRuntimeScaleMonitoringEnabled: false
      linuxFxVersion: isReserved ? linuxRuntime : json('null')
      keyVaultReferenceIdentity: 'SystemAssigned'
      appSettings: [
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~3'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
        {
          name: 'NotificationHubName'
          value: '@Microsoft.KeyVault(VaultName=${keyvaultReferenceName};SecretName=ntfName)'
        }
        {
          name: 'AzureWebJobsStorage'
          value: composedStorageConnectionString
        }
        {
          name: 'AzureAd__Instance'
          value: environment().authentication.loginEndpoint
        }
        {
          name: 'AzureAd__Domain'
          value:  '@Microsoft.KeyVault(VaultName=${keyvaultReferenceName};SecretName=azureAdPrimaryDomain)'
        }
        {
          name: 'AzureAd__ClientId'
          value:  '@Microsoft.KeyVault(VaultName=${keyvaultReferenceName};SecretName=azureAdWebapiClientId)'
        }
        {
          name: 'AzureAd__ClientSecret'
          value:  '@Microsoft.KeyVault(VaultName=${keyvaultReferenceName};SecretName=azureAdWebapiClientSecret)'
        }
        {
          name: 'AzureAd__TenantId'
          value:  '@Microsoft.KeyVault(VaultName=${keyvaultReferenceName};SecretName=azureAdPrimaryTenantId)'
        }
        {
          name: 'DownstreamApi__BaseUrl'
          value:  'https://graph.microsoft.com/v1.0'
        }
        {
          name: 'DownstreamApi__Scopes'
          value:  'user.read'
        }
      ]
      connectionStrings: [
        {
          name: 'BlobStorageConnString'
          connectionString: '@Microsoft.KeyVault(VaultName=${keyvaultReferenceName};SecretName=storageConnectionString)'
          type: 'Custom'
        }
        {
          name: 'AcsConnString'
          connectionString: '@Microsoft.KeyVault(VaultName=${keyvaultReferenceName};SecretName=acsPrimaryConnectionString)'
          type: 'Custom'
        }
      ]
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}



var appInsightName = take(deploymentName, sharedVars.appInsightMaxLength - length('-${sharedVars.appInsightPrefix}-${environmentName}-${version}'))
resource applicationInsights 'Microsoft.Insights/components@2020-02-02-preview' = {
  name: toLower('${sharedVars.appInsightPrefix}-${appInsightName}-${environmentName}-${version}')
  location: location
  tags: resourceTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
}

// sample output resource information, can be deleted when we got actual output requirements
output storageInfo object = {
  storageId: storage.id
}
output acsName string = acs.name
output acsResourceGroup string = resourceGroup().name
