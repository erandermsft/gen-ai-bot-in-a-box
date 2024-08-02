param location string
param appServicePlanName string
param appServiceName string
param msiID string
param msiClientID string
param linuxFxVersion string
param implementation string
param sku string = 'S1'
param tags object = {}
param deploymentName string
param searchName string

param aiServicesName string
param cosmosName string

param privateEndpointSubnetId string
param appSubnetId string
param privateDnsZoneId string


resource aiServices 'Microsoft.CognitiveServices/accounts@2023-05-01' existing = {
  name: aiServicesName
}

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' existing = {
  name: cosmosName
}

resource search 'Microsoft.Search/searchServices@2023-11-01' existing = if (!empty(searchName)) {
  name: searchName
}

resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: sku
    capacity: 1
  }
  properties: {
    reserved: true
  }
  kind: 'linux'
}

resource appService 'Microsoft.Web/sites@2023-12-01' = {
  name: appServiceName
  location: location
  tags: union(tags, { 'azd-service-name': 'genai-bot-app' })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${msiID}': {}
    }
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    virtualNetworkSubnetId: appSubnetId
    siteConfig: {
      ipSecurityRestrictions: [
        // Allow Bot Service
        { action: 'Allow', ipAddress: 'AzureBotService', priority: 100, tag: 'ServiceTag' }
        // Allow Teams Messaging IPs
        { action: 'Allow', ipAddress: '13.107.64.0/18', priority: 200 }
        { action: 'Allow', ipAddress: '52.112.0.0/14', priority: 201 }
        { action: 'Allow', ipAddress: '52.120.0.0/14', priority: 202 }
        { action: 'Allow', ipAddress: '52.238.119.141/32', priority: 203 }
      ]
      publicNetworkAccess: 'Enabled'
      ipSecurityRestrictionsDefaultAction: 'Deny'
      scmIpSecurityRestrictionsDefaultAction: 'Allow'
      http20Enabled: true
      linuxFxVersion: linuxFxVersion
      appCommandLine: startsWith(linuxFxVersion, 'python') ? 'gunicorn --bind 0.0.0.0 --timeout 600 app:app --worker-class aiohttp.GunicornWebWorker' : ''
      appSettings: [
        {
          name: 'MicrosoftAppType'
          value: 'UserAssignedMSI'
        }
        {
          name: 'MicrosoftAppId'
          value: msiClientID
        }
        {
          name: 'MicrosoftAppTenantId'
          value: tenant().tenantId
        }
        {
          name: 'GEN_AI_IMPLEMENTATION'
          value: implementation
        }
        {
          name: 'AZURE_OPENAI_API_ENDPOINT'
          value: aiServices.properties.endpoint
        }
        {
          name: 'AZURE_OPENAI_API_VERSION'
          value: '2024-05-01-preview'
        }
        {
          name: 'AZURE_OPENAI_DEPLOYMENT_NAME'
          value: deploymentName
        }
        {
          name: 'AZURE_OPENAI_ASSISTANT_ID'
          value: 'YOUR_ASSISTANT_ID'
        }
        {
          name: 'AZURE_COSMOSDB_ENDPOINT'
          value: cosmos.properties.documentEndpoint
        }
        {
          name: 'AZURE_COSMOSDB_DATABASE_ID'
          value: 'GenAIBot'
        }
        {
          name: 'AZURE_COSMOSDB_CONTAINER_ID'
          value: 'Conversations'
        }
        {
          name: 'AZURE_SEARCH_API_ENDPOINT'
          value: !empty(searchName) ? 'https://${search.name}.search.windows.net' : ''
        }
        {
          name: 'AZURE_SEARCH_INDEX'
          value: 'index-name'
        }
        {
          name: 'MAX_TURNS'
          value: '10'
        }
        {
          name: 'LLM_INSTRUCTIONS'
          value: 'Answer the questions as accurately as possible using the provided functions.'
        }
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: startsWith(linuxFxVersion,'dotnet') ? 'false' : 'true'
        }
        {
          name: 'ENABLE_ORYX_BUILD'
          value: startsWith(linuxFxVersion,'dotnet') ? 'false' : 'true'
        }
        {
          name: 'DEBUG'
          value: 'true'
        }
      ]
    }
  }
}


resource appPrivateEndpoint 'Microsoft.Network/privateEndpoints@2021-05-01' = {
  name: 'pl-${appServiceName}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'private-endpoint-connection'
        properties: {
          privateLinkServiceId: appService.id
          groupIds: [ 'sites' ]
        }
      }
    ]
  }
  resource privateDnsZoneGroup 'privateDnsZoneGroups' = {
    name: 'zg-${appServiceName}'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'default'
          properties: {
            privateDnsZoneId: privateDnsZoneId
          }
        }
      ]
    }
  }
}

output appName string = appService.name
output hostName string = appService.properties.defaultHostName
