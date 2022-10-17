@description('Optional. A name that will be prepended to all deployed resources. Defaults to an alphanumeric id that is unique to the resource group.')
param applicationName string = 'zrhaaca-${uniqueString(resourceGroup().id)}'

@description('Optional. The Azure region (location) to deploy to. Must be a region that supports availability zones. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Optional. An Azure tags object for tagging parent resources that support tags.')
param tags object = {
  Project: 'Azure highly-available zone-redundant Azure Container App'
}

@description('Optional. Name of the Log Analytics workspace to create. Defaults to \'\${applicationName}-law\'')
param logAnalyticsWorkspaceName string = '${applicationName}-law'

@description('Optional. Name of the Application Insights workspace to create. Defaults to \'\${applicationName}-appsins\'')
param appInsightsName string = '${applicationName}-appsins'

@description('Optional. Name of the Azure Container Registry to create. Defaults to \'\${applicationName}acr\'')
param containerRegistryName string = replace('${applicationName}acr', '-', '')

@description('Optional. Name of the Container App Environment to create. Defaults to \'\${applicationName}-env\'')
param containerAppEnvironmentName string = '${applicationName}-env'

@description('Optional. Name of the Cosmos DB Account to create. Defaults to \'\${applicationName}-cosmos\'')
param cosmosDbAccountName string = '${applicationName}-cosmos'

@description('Optional. Name of the Azure Cache for Redis instance to create. Defaults to \'\${applicationName}-redis\'')
param redisCacheName string = '${applicationName}-redis'

@description('Optional. Name of the Azure Service Bus to create. Defaults to \'\${applicationName}sb\'')
param serviceBusName string = replace('${applicationName}sb', '-', '')

@description('Optional. Name of the Azure SQL Server to create. Defaults to \'\${applicationName}-sql\'')
param sqlServerName string = '${applicationName}-sql'

@description('Optional. SQL admin username. Defaults to \'\${applicationName}-admin\'')
param sqlAdmin string = '${applicationName}-admin'

@description('Optional. A password for the Azure SQL server admin user. Defaults to a new GUID.')
@secure()
param sqlAdminPassword string = newGuid()

@description('Optional. Name of the Azure Storage account to create. Defaults to \'\${applicationName}stor\'')
param storageAccountName string = take(toLower(replace('${applicationName}stor', '-', '')), 24)

@description('Optional. Name of the Azure Key Vault to create. Defaults to \'\${applicationName}-kv\'')
param keyVaultName string = '${applicationName}-kv'

var vnet = '${applicationName}-vnet'

var containerAppName = 'frontend'

var databaseName = 'reddog'
var blobContainerName = 'receipts'
var cosmosDatabaseName = 'reddog'
var cosmosCollectionName = 'loyalty'

var images = [
  'ghcr.io/azure/reddog-retail-demo/reddog-retail-accounting-service:latest'
  'ghcr.io/azure/reddog-retail-demo/reddog-retail-bootstrapper:latest'
  'ghcr.io/azure/reddog-retail-demo/reddog-retail-loyalty-service:latest'
  'ghcr.io/azure/reddog-retail-demo/reddog-retail-make-line-service:latest'
  'ghcr.io/azure/reddog-retail-demo/reddog-retail-order-service:latest'
  'ghcr.io/azure/reddog-retail-demo/reddog-retail-receipt-generation-service:latest'
  'ghcr.io/azure/reddog-retail-demo/reddog-traefik:latest'
  'ghcr.io/azure/reddog-retail-demo/reddog-retail-ui:latest'
  'ghcr.io/azure/reddog-retail-demo/reddog-retail-virtual-customers:latest'
  'ghcr.io/azure/reddog-retail-demo/reddog-retail-virtual-worker:latest'
]

// ROLE DEFINITION
var acrPullRoleDefinition = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')

// PRIVATE DNS VARIABLES
var privateLinkContainerRegistryDnsNames = {
  AzureCloud: 'privatelink.azurecr.io'
  AzureUSGovernment: 'privatelink.azurecr.us'
  AzureChinaCloud: 'privatelink.azurecr.cn'
}

var privateLinkCosmosDnsNames = {
  AzureCloud: 'privatelink.documents.azure.com'
  AzureUSGovernment: 'privatelink.documents.azure.us'
  AzureChinaCloud: 'privatelink.documents.azure.cn'
}

var privateLinkRedisDnsNames = {
  AzureCloud: 'privatelink.redis.cache.windows.net'
  AzureUSGovernment: 'privatelink.redis.cache.usgovcloudapi.net'
  AzureChinaCloud: 'privatelink.redis.cache.chinacloudapi.cn'
}

var privateLinkServiceBusDnsNames = {
  AzureCloud: 'privatelink.servicebus.windows.net'
  AzureUSGovernment: 'privatelink.servicebus.usgovcloudapi.net'
  AzureChinaCloud: 'privatelink.servicebus.chinacloudapi.cn'
}

var privateLinkKeyVaultDnsNames = {
  AzureCloud: 'privatelink.vaultcore.azure.net'
  AzureUSGovernment: 'privatelink.vaultcore.usgovcloudapi.net'
  AzureChinaCloud: 'privatelink.vaultcore.azure.cn'
}

// LOG ANALYTICS
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
   features: {
    searchVersion: 1
   }
   sku: {
    name: 'PerGB2018'
   } 
  }
}

// APPLICATION INSIGHTS
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

// VIRTUAL NETWORK
resource vnetResource 'Microsoft.Network/virtualNetworks@2022-05-01' = {
  name: vnet
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      // [0] Container App Environment integration subnet
      {
        name: 'containerappenv-backend-subnet'
        properties: {
          addressPrefix: '10.0.0.0/23'
        }
      }
      // [1] Container Registry integration subnet
      {
        name: 'containerregistry-backend-subnet'
        properties: {
          addressPrefix: '10.0.2.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      // [2] Cosmos DB Integration subnet
      {
        name: 'cosmosdb-backend-subnet'
        properties: {
          addressPrefix: '10.0.3.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'         
        }
      }
      // [3] Redis Cache Integration subnet
      {
        name: 'redis-backend-subnet'
        properties: {
          addressPrefix: '10.0.4.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      // [4] Service Bus Integration subnet
      {
        name: 'servicebus-backend-subnet'
        properties: {
          addressPrefix: '10.0.5.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      // [5] SQL Integration subnet
      {
        name: 'sql-backend-subnet'
        properties: {
          addressPrefix: '10.0.6.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      // [6] Azure Storage Subnet
      {
        name: 'storage-backend-subnet'
        properties: {
          addressPrefix: '10.0.7.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      // [7] Key Vault private endpoint subnet
      {
        name: 'keyvault-subnet'
        properties: {
          addressPrefix: '10.0.8.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]   
  }
}

// CONTAINER REGISTRY
// TODO: Create Managed Identity ACR Task: https://learn.microsoft.com/en-us/azure/container-registry/container-registry-private-link#disable-public-access
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2022-02-01-preview' = {
  name: containerRegistryName
  location: location
  tags: tags
  sku: {
    name: 'Premium'
  }
  properties: {
    zoneRedundancy: 'Enabled'
    publicNetworkAccess: 'Disabled'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// WOULD IMPORT ACR IMAGES MODULE WORK HERE?
module acrImport 'br/public:deployment-scripts/import-acr:1.0.1' = {
  name: 'ImportAcrImages'
  params: {
    acrName: containerRegistry.name
    images: images
    location: location
  }
}

// COSMOS DB ACCOUNT
resource cosmosDb 'Microsoft.DocumentDB/databaseAccounts@2022-08-15' = {
  name: cosmosDbAccountName
  location: location
  tags: tags
  properties: {
    databaseAccountOfferType: 'Standard'
    locations: [
      {
        locationName: location
        isZoneRedundant: true
        failoverPriority: 0
      }
    ]
    publicNetworkAccess: 'Disabled'
    backupPolicy:{
      type: 'Continuous'
    }
  }
  resource cosmosDatabase 'sqlDatabases' = {
    name: cosmosDatabaseName
    location: location
    properties: {
      resource: {
        id: cosmosDatabaseName
      }
      options: {
        throughput: 400
      }
    }
    resource container 'containers' = {
      name: cosmosCollectionName
      location: location
      properties: {
        resource: {
          id: cosmosCollectionName
          partitionKey: {
            kind: 'Hash'
            paths: [
              '/id'
            ]
          }
        }
      }
    }
  }
}

// AZURE CACHE FOR REDIS PREMIUM
resource redisResource 'Microsoft.Cache/redis@2022-06-01' = {
  name: redisCacheName
  location: location
  tags: tags
  zones: [
    '1'
    '2'
    '3'
  ]
  properties: {
    sku: {
      capacity: 1
      family: 'P'
      name: 'Premium'
    }
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Disabled'
    replicasPerMaster: 2
    replicasPerPrimary: 2
  }
}

// SERVICE BUS PREMIUM
resource serviceBusResource 'Microsoft.ServiceBus/namespaces@2022-01-01-preview' = {
  name: serviceBusName
  location: location
  tags: tags
  sku: {
    name: 'Premium'
    capacity: 1
    tier: 'Premium'
  }
  properties: {
    zoneRedundant: true
  }
  // TODO: Add Service Bus Resources
}

// AZURE SQL
resource sqlResource 'Microsoft.Sql/servers@2022-05-01-preview' = {
  name: sqlServerName
  location: location
  tags: tags
  properties: {
   publicNetworkAccess: 'Disabled' 
   administratorLogin: sqlAdmin
   administratorLoginPassword: sqlAdminPassword
  }
  resource sqlDb 'databases' = {
    name: databaseName
    location: location
    tags: tags
    sku: {
      name: 'P1'
      tier: 'Premium'
    }
    properties: {
     zoneRedundant: true 
    }
  }
}

// STORAGE ACCOUNT
resource storageResource 'Microsoft.Storage/storageAccounts@2022-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_ZRS'
  }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Disabled'
    accessTier: 'Hot'
  }
  resource blobService 'blobServices' = {
    name: 'default'
    resource blobContainer 'containers' = {
      name: blobContainerName
    }
  }
}

// KEY VAULT
resource keyVaultResource 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A' 
      name: 'standard'
    }
    tenantId: tenant().tenantId
    publicNetworkAccess: 'disabled'
    enabledForTemplateDeployment: true
    accessPolicies: [
      
    ]
  }
}

// CONTAINER APP ENVIRONMENT
resource env 'Microsoft.App/managedEnvironments@2022-06-01-preview' = {
  name:  containerAppEnvironmentName
  location: location
  tags: tags
  sku: {
    name: 'Consumption'
  }
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    vnetConfiguration: {
      internal: false
      infrastructureSubnetId: vnetResource.properties.subnets[0].id
      runtimeSubnetId: vnetResource.properties.subnets[0].id
    }
    zoneRedundant: true
  }
}

// DAPR COMPONENTS
// TODO: Use Secrets from Key Vault instead  
resource pubSubComponent 'Microsoft.App/managedEnvironments/daprComponents@2022-06-01-preview' = {
  name: 'reddog.pubsub'
  parent: env
  properties: {
    componentType: 'pubsub.azure.servicebus'
    version: 'v1'
    metadata: [
      {
        name: 'connectionString'
        secretRef: 'sb-root-connectionstring'
      }
    ]
    secrets: [
      {
        name: 'sb-root-connectionstring'
        value: listKeys('${serviceBusResource.id}/AuthorizationRules/RootManageSharedAccessKey', serviceBusResource.apiVersion).primaryConnectionString
      }
    ]
    scopes: [
      'accounting-service'
      'loyalty-service'
      'make-line-service'
      'order-service'
      'receipt-generation-service'
    ]   
  }
}

resource receiptBindingComponent 'Microsoft.App/managedEnvironments/daprComponents@2022-06-01-preview' = {
  name: 'reddog.binding.receipt'
  parent: env
  properties: {
    componentType: 'bindings.azure.blobstorage'
    version: 'v1'
    metadata: [
      {
        name: 'storageAccount'
        value: storageAccountName
      }
      {
        name: 'container'
        value: storageResource::blobService::blobContainer.name
      }
      {
        name: 'storageAccessKey'
        secretRef: 'blob-storage-key'
      }
    ]
    secrets: [
      {
        name: 'blob-storage-key'
        value: listkeys(storageResource.id, storageResource.apiVersion).keys[0].value
      }
    ]
    scopes: [
      'receipt-generation-service'
    ]   
  }
}

resource virtualWorkerBindingComponent 'Microsoft.App/managedEnvironments/daprComponents@2022-06-01-preview' = {
  name: 'orders'
  parent: env
  properties: {
    componentType: 'bindings.cron'
    version: 'v1'
    metadata: [
      {
        name: 'schedule'
        value: '@every 15s'
      }
    ]
    scopes: [
      'virtual-worker'
    ]   
  }
}

resource loyaltyStateComponent 'Microsoft.App/managedEnvironments/daprComponents@2022-06-01-preview' = {
  name: 'reddog.state.loyalty'
  parent: env
  properties: {
    componentType: 'state.azure.cosmosdb'
    version: 'v1'
    metadata: [
      {
        name: 'url'
        value: 'https://${cosmosDb.properties.documentEndpoint}:443/'
      }
      {
        name: 'database'
        value: cosmosDb::cosmosDatabase.name
      }
      {
        name: 'collection'
        value: cosmosDb::cosmosDatabase::container.name
      }
      {
        name: 'masterKey'
        secretRef: 'cosmos-primary-rw-key'
      }
    ]
    secrets: [
      {
        name: 'cosmos-primary-rw-key'
        value: listkeys(cosmosDb.id, cosmosDb.apiVersion).primaryMasterKey
      }
    ]
    scopes: [
      'loyalty-service'
    ]
  }
}

resource makelineStateComponent 'Microsoft.App/managedEnvironments/daprComponents@2022-06-01-preview' = {
  name: 'reddog.state.makeline'
  parent: env
  properties: {
    componentType: 'state.redis'
    version: 'v1'
    metadata: [
      {
        name: 'redisHost'
        value: '${redisResource.properties.hostName}:${redisResource.properties.sslPort}'
      }
      {
        name: 'redisPassword'
        value: 'redis-password'
      }
      {
        name: 'enableTLS'
        value: 'true'
      }
    ]
    secrets: [
      {
        name: 'redis-password'
        value: listKeys(redisResource.id, redisResource.apiVersion).primaryKey
      }
    ]
    scopes: [
      'make-line-service'
    ]
  }
}

// CONTAINER APPS
resource containerApp 'Microsoft.App/containerApps@2022-06-01-preview' = {
  name: containerAppName
  location: location
  properties: {
    managedEnvironmentId: env.id
    configuration: {
      registries: [
        {
          identity: 'system'
          server: containerRegistry.properties.loginServer
        }
      ]
      activeRevisionsMode: 'Multiple'
      ingress: {
        external: true
        targetPort: 80
        transport: 'http'
        allowInsecure: true
      }
    }
    template: {
      containers: [
        {
          name: containerAppName
          image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
          env: [
            {
              name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
              value: appInsights.properties.InstrumentationKey
            }
            {
              name: 'APPINSIGHTS_CONNECTION_STRING'
              value: appInsights.properties.ConnectionString
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// PRIVATE DNS ZONES
resource privateContainerRegistryDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateLinkContainerRegistryDnsNames[environment().name]
  location: 'global'
  tags: tags

  resource privateContainerRegistryDnsZoneVNetLink 'virtualNetworkLinks' = {
    name: '${last(split(vnetResource.id, '/'))}-vnetlink'
    location: 'global'
    properties: {
      registrationEnabled: false
      virtualNetwork: {
        id: vnetResource.id
      }   
    }
  }
}

resource privateCosmosDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateLinkCosmosDnsNames[environment().name]
  location: 'global'
  tags: tags
  resource privateCosmosDnsZoneVNetLink 'virtualNetworkLinks' = {
    name: '${last(split(vnetResource.id, '/'))}-vnetlink'
    location: 'global'
    properties: {
      registrationEnabled: false
      virtualNetwork: {
        id: vnetResource.id
      }   
    }
  }
}

resource privateRedisDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateLinkRedisDnsNames[environment().name]
  location: 'global'
  tags: tags
  resource privateRedisDnsZoneVNetLink 'virtualNetworkLinks' = {
    name: '${last(split(vnetResource.id, '/'))}-vnetlink'
    location: 'global'
    properties: {
      registrationEnabled: false
      virtualNetwork: {
        id: vnetResource.id
      }   
    }
  }
}

resource privateServiceBusDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateLinkServiceBusDnsNames[environment().name]
  location: 'global'
  tags: tags
  resource privateServiceBusDnsZoneVNetLink 'virtualNetworkLinks' = {
    name: '${last(split(vnetResource.id, '/'))}-vnetlink'
    location: 'global'
    properties: {
      registrationEnabled: false
      virtualNetwork: {
        id: vnetResource.id
      }
    }
  }
}

resource privateSqlDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink${environment().suffixes.sqlServerHostname}'
  location: 'global'
  tags: tags
  resource privateSqlDnsZoneVNetLink 'virtualNetworkLinks' = {
    name: '${last(split(vnetResource.id, '/'))}-vnetlink'
    location: 'global'
    properties: {
      registrationEnabled: false
      virtualNetwork: {
        id: vnetResource.id
      } 
    }
  }
}

resource privateBlobsDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.blob.${environment().suffixes.storage}'
  location: 'global'
  tags: tags
  resource privateBlobsDnsZoneVNetLink 'virtualNetworkLinks' = {
    name: '${last(split(vnetResource.id, '/'))}-vnetlink'
    location: 'global'
    properties: {
      registrationEnabled: false
      virtualNetwork: {
        id: vnetResource.id
      }
    }
  }
}

resource privateFilesDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.file.${environment().suffixes.storage}'
  location: 'global'
  tags: tags
  resource privateFilesDnsZoneVNetLink 'virtualNetworkLinks' = {
    name: '${last(split(vnetResource.id, '/'))}-vnetlink'
    location: 'global'
    properties:{
      registrationEnabled: false
      virtualNetwork:{
        id: vnetResource.id
      }
    }
  }
}

resource privateTablesDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.table.${environment().suffixes.storage}'
  location: 'global'
  tags: tags
  resource privateTablesDnsZoneVNetLink 'virtualNetworkLinks' = {
    name: '${last(split(vnetResource.id, '/'))}-vnetlink'
    location: 'global'
    properties:{
      registrationEnabled: false
      virtualNetwork:{
        id: vnetResource.id
      }
    }
  }
}

resource privateQueuesDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.queue.${environment().suffixes.storage}'
  location: 'global'
  tags: tags
  resource privateQueuesDnsZoneVNetLink 'virtualNetworkLinks' = {
    name: '${last(split(vnetResource.id, '/'))}-vnetlink'
    location: 'global'
    properties:{
      registrationEnabled: false
      virtualNetwork:{
        id: vnetResource.id
      }
    }
  }
}

resource privateKeyvaultDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateLinkKeyVaultDnsNames[environment().name]
  location: 'global'
  tags: tags
  resource privateSitesDnsZoneVNetLink 'virtualNetworkLinks' = {
    name: '${last(split(vnetResource.id, '/'))}-vnetlink'
    location: 'global'
    properties:{
      registrationEnabled: false
      virtualNetwork:{
        id: vnetResource.id
      }
    }
  }
}

// PRIVATE ENDPOINTS
resource containerRegistryPepResource 'Microsoft.Network/privateEndpoints@2022-05-01' = {
  name: '${containerRegistry.name}-pep'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: vnetResource.properties.subnets[1].id
    }   
    privateLinkServiceConnections: [
      {
        name: 'peplink'
        properties: {
          privateLinkServiceId: containerRegistry.id
          groupIds: [
            'registry'
          ]
        }
      }
    ]
  }

  resource privateDnsZoneGroup 'privateDnsZoneGroups' = {
    name: 'dnszonegroup'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'config'
          properties: {
            privateDnsZoneId: privateContainerRegistryDnsZone.id
          }
        }
      ]   
    }
  }
}

resource cosmosPepResource 'Microsoft.Network/privateEndpoints@2022-05-01' = {
  name: '${cosmosDb.name}-pep'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: vnetResource.properties.subnets[2].id
    }
    privateLinkServiceConnections: [
      {
        name: 'peplink'
        properties: {
          privateLinkServiceId: cosmosDb.id
          groupIds: [
            'sql'
          ]
        }
      }
    ]
  }

  resource privateDnsZoneGroups 'privateDnsZoneGroups' = {
    name: 'dnszonegroup'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'config'
          properties: {
            privateDnsZoneId: privateCosmosDnsZone.id
          }
        }
      ]   
    }
  }
}

resource redisPepResource 'Microsoft.Network/privateEndpoints@2022-05-01' = {
  name: '${redisResource.name}-pep'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: vnetResource.properties.subnets[3].id
    }   
    privateLinkServiceConnections: [
      {
        name: 'peplink'
        properties: {
          privateLinkServiceId: redisResource.id
          groupIds: [
            'redisCache'
          ]
        }
      }
    ]
  }
  resource privateDnsZoneGroups 'privateDnsZoneGroups' = {
    name: 'dnszonegroup'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'config'
          properties: {
            privateDnsZoneId: privateRedisDnsZone.id
          }
        }
      ]   
    }
  }
}

resource serviceBusPepResource 'Microsoft.Network/privateEndpoints@2022-05-01' = {
  name: '${serviceBusResource.name}-pep'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: vnetResource.properties.subnets[4].id
    }
    privateLinkServiceConnections: [
      {
        name: 'peplink'
        properties: {
          privateLinkServiceId: serviceBusResource.id
          groupIds: [
            'namespace'
          ]
        }
      }
    ]
  }
  resource privateDnsZoneGroups 'privateDnsZoneGroups' = {
    name: 'dnszonegroup'
    properties: {
      privateDnsZoneConfigs: [
       {
        name: 'config'
        properties: {
          privateDnsZoneId: privateServiceBusDnsZone.id
        }
       } 
      ]
    }
  }
}

resource sqlPepResource 'Microsoft.Network/privateEndpoints@2022-05-01' = {
  name: '${sqlResource.name}-pep'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: vnetResource.properties.subnets[5].id
    }
    privateLinkServiceConnections: [
      {
        name: 'peplink'
        properties: {
          privateLinkServiceId: sqlResource.id
          groupIds: [
            'sqlServer'
          ]
        }
      }
    ]   
  }
  resource privateDnsZoneGroups 'privateDnsZoneGroups' = {
    name: 'dnszonegroup'
    properties: {
     privateDnsZoneConfigs: [
      {
        name: 'config'
        properties: {
          privateDnsZoneId: privateSqlDnsZone.id
        }
      }
     ] 
    }
  }
}

resource blobStoragePepResource 'Microsoft.Network/privateEndpoints@2022-01-01' = {
  name: '${storageResource.name}-blob-pep'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: vnetResource.properties.subnets[6].id
    }
    privateLinkServiceConnections: [
      {
        name: 'peplink'
        properties: {
          privateLinkServiceId: storageResource.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
  resource privateDnsZoneGroup 'privateDnsZoneGroups' = {
    name: 'dnszonegroup'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'config'
          properties: {
            privateDnsZoneId: privateBlobsDnsZone.id
          }
        }
      ]
    }
  }
}

resource tableStoragePepResource 'Microsoft.Network/privateEndpoints@2022-01-01' = {
  name: '${storageResource.name}-table-pep'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: vnetResource.properties.subnets[6].id
    }
    privateLinkServiceConnections: [
      {
        name: 'peplink'
        properties: {
          privateLinkServiceId: storageResource.id
          groupIds: [
            'table'
          ]
        }
      }
    ]
  }
  resource privateDnsZoneGroup 'privateDnsZoneGroups' = {
    name: 'dnszonegroup'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'config'
          properties: {
            privateDnsZoneId: privateTablesDnsZone.id
          }
        }
      ]
    }
  }
}

resource queueStoragePepResource 'Microsoft.Network/privateEndpoints@2022-01-01' = {
  name: '${storageResource.name}-queue-pep'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: vnetResource.properties.subnets[6].id
    }
    privateLinkServiceConnections: [
      {
        name: 'peplink'
        properties: {
          privateLinkServiceId: storageResource.id
          groupIds: [
            'queue'
          ]
        }
      }
    ]
  }
  resource privateDnsZoneGroup 'privateDnsZoneGroups' = {
    name: 'dnszonegroup'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'config'
          properties: {
            privateDnsZoneId: privateQueuesDnsZone.id
          }
        }
      ]
    }
  }
}

resource fileStoragePepResource 'Microsoft.Network/privateEndpoints@2022-01-01' = {
  name: '${storageResource.name}-file-pep'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: vnetResource.properties.subnets[6].id
    }
    privateLinkServiceConnections: [
      {
        name: 'peplink'
        properties: {
          privateLinkServiceId: storageResource.id
          groupIds: [
            'file'
          ]
        }
      }
    ]
  }
  resource privateDnsZoneGroup 'privateDnsZoneGroups' = {
    name: 'dnszonegroup'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'config'
          properties: {
            privateDnsZoneId: privateFilesDnsZone.id
          }
        }
      ]
    }
  }
}

resource keyvaultPepResource 'Microsoft.Network/privateEndpoints@2022-01-01' = {
  name: '${keyVaultResource.name}-pep'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: vnetResource.properties.subnets[7].id
    }
    privateLinkServiceConnections: [
      {
        name: 'peplink'
        properties: {
          privateLinkServiceId: keyVaultResource.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
  resource privateDnsZoneGroup 'privateDnsZoneGroups' = {
    name: 'dnszonegroup'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'config'
          properties: {
            privateDnsZoneId: privateKeyvaultDnsZone.id
          }
        }
      ]
    }
  }
}

// ROLE ASSIGNMENTS
resource acaAcrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, containerApp.id, acrPullRoleDefinition)
  scope: containerRegistry
  properties: {
    principalId: containerApp.identity.principalId
    roleDefinitionId: acrPullRoleDefinition
    principalType: 'ServicePrincipal'
  }
}
