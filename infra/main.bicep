// ──────────────────────────────────────────────
//  StayBright Hotels — Azure Infrastructure
//  Single App Service hosting backend API + frontend SPA
// ──────────────────────────────────────────────

targetScope = 'resourceGroup'

@description('Base name for all resources')
param appName string = 'staybright'

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('App Service Plan SKU')
@allowed(['F1', 'B1', 'B2', 'S1', 'P1v3'])
param appServicePlanSku string = 'F1'

@description('Azure OpenAI endpoint URL')
@secure()
param azureOpenAiEndpoint string = ''

@description('Azure OpenAI API key')
@secure()
param azureOpenAiApiKey string = ''

@description('Azure OpenAI deployment/model name')
param azureOpenAiDeploymentName string = 'gpt-4o'

// ── App Service Plan ──
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${appName}-plan'
  location: location
  kind: 'linux'
  sku: {
    name: appServicePlanSku
  }
  properties: {
    reserved: true // Required for Linux
  }
}

// ── App Service (hosts backend + frontend) ──
resource webApp 'Microsoft.Web/sites@2023-12-01' = {
  name: '${appName}-app'
  location: location
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOTNETCORE|10.0'
      alwaysOn: appServicePlanSku != 'F1'
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      appSettings: [
        {
          name: 'AZURE_OPENAI_ENDPOINT'
          value: azureOpenAiEndpoint
        }
        {
          name: 'AZURE_OPENAI_API_KEY'
          value: azureOpenAiApiKey
        }
        {
          name: 'AZURE_OPENAI_DEPLOYMENT_NAME'
          value: azureOpenAiDeploymentName
        }
        {
          name: 'ASPNETCORE_ENVIRONMENT'
          value: 'Production'
        }
      ]
    }
  }
}

// ── Outputs ──
output appServiceName string = webApp.name
output appServiceUrl string = 'https://${webApp.properties.defaultHostName}'
output mcpEndpoint string = 'https://${webApp.properties.defaultHostName}/mcp'
output openApiEndpoint string = 'https://${webApp.properties.defaultHostName}/openapi/v1.json'
