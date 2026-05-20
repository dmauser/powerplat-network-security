@description('Prefix used for all resource names.')
param prefix string

@description('Environment suffix used for resource names.')
param env string

@description('Azure location for the SQL deployment.')
param location string

@description('Tags applied to deployed resources.')
param tags object

@description('Resource ID of the user-assigned managed identity configured as SQL administrator.')
param uamiResourceId string

@description('Principal ID of the user-assigned managed identity configured as SQL administrator.')
param uamiPrincipalId string

@description('Name of the user-assigned managed identity configured as SQL administrator.')
param uamiName string

@description('Optional. Resource ID of the Log Analytics workspace for diagnostic settings. Leave empty to skip.')
param logAnalyticsWorkspaceId string = ''

var sqlServerName = 'sql-${prefix}-${env}-${uniqueString(resourceGroup().id)}'
var sqlDatabaseName = 'salesdb'

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: sqlServerName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uamiResourceId}': {}
    }
  }
  properties: {
    administrators: {
      administratorType: 'ActiveDirectory'
      principalType: 'Application'
      login: uamiName
      sid: uamiPrincipalId
      tenantId: subscription().tenantId
      azureADOnlyAuthentication: true
    }
    publicNetworkAccess: 'Disabled'
    minimalTlsVersion: '1.2'
  }
}

resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  name: sqlDatabaseName
  parent: sqlServer
  location: location
  sku: {
    name: 'GP_S_Gen5_1'
    tier: 'GeneralPurpose'
  }
  properties: {
    autoPauseDelay: 60
    minCapacity: json('0.5')
    maxSizeBytes: 2147483648
  }
}

output sqlServerName string = sqlServer.name
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName
output sqlServerId string = sqlServer.id
output sqlDatabaseName string = sqlDatabase.name
output sqlDatabaseId string = sqlDatabase.id

// Diagnostic settings on the SQL database resource (not the server).
resource sqlDiagSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: 'diag-sqldb'
  scope: sqlDatabase
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      { category: 'SQLSecurityAuditEvents', enabled: true }
      { category: 'Errors',                 enabled: true }
      { category: 'Timeouts',               enabled: true }
    ]
    metrics: [
      { category: 'Basic',                  enabled: true }
      { category: 'InstanceAndAppAdvanced', enabled: true }
    ]
  }
}
