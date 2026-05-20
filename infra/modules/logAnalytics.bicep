@description('Prefix used for all resource names.')
param prefix string

@description('Environment suffix used for resource names.')
param env string

@description('Azure location for the Log Analytics workspace.')
param location string

@description('Tags applied to deployed resources.')
param tags object

@description('Data retention period in days. Minimum 30, maximum 730.')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

var workspaceName = 'law-${prefix}-${env}-${uniqueString(resourceGroup().id)}'

// SKU PerGB2018 is the standard pay-as-you-go tier (the legacy Free SKU is capped at 500 MB/day
// and is no longer appropriate for production or lab workloads).
// Public network access for ingestion and query is enabled for lab simplicity.
// Security note: for production hardening consider disabling public access and
// adding an Azure Monitor Private Link Scope (AMPLS).
// See: https://learn.microsoft.com/en-us/azure/azure-monitor/logs/private-link-security
resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

output workspaceId string = workspace.id
output customerId string = workspace.properties.customerId
output workspaceName string = workspace.name
