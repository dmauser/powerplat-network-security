@description('Region for the flow log resource. Must match the target virtual network region.')
param location string

@description('Name of the flow log resource.')
param flowLogName string

@description('Resource ID of the target virtual network.')
param vnetId string

@description('Resource ID of the flow logs storage account.')
param storageAccountId string

@description('Resource ID of the Log Analytics workspace for Traffic Analytics.')
param logAnalyticsWorkspaceId string

@description('Region of the Log Analytics workspace.')
param logAnalyticsWorkspaceRegion string

@description('Customer ID (GUID) of the Log Analytics workspace.')
param logAnalyticsWorkspaceGuid string

@description('Tags applied to deployed resources.')
param tags object

@description('Name of the regional Network Watcher resource (for example, NetworkWatcher_eastus).')
param networkWatcherName string

resource networkWatcher 'Microsoft.Network/networkWatchers@2024-05-01' existing = {
  name: networkWatcherName
}

resource flowLog 'Microsoft.Network/networkWatchers/flowLogs@2024-05-01' = {
  name: flowLogName
  parent: networkWatcher
  location: location
  tags: tags
  properties: {
    enabled: true
    targetResourceId: vnetId
    storageId: storageAccountId
    format: {
      type: 'JSON'
      version: 2
    }
    retentionPolicy: {
      enabled: true
      days: 7
    }
    flowAnalyticsConfiguration: {
      networkWatcherFlowAnalyticsConfiguration: {
        enabled: true
        workspaceId: logAnalyticsWorkspaceGuid
        workspaceRegion: logAnalyticsWorkspaceRegion
        workspaceResourceId: logAnalyticsWorkspaceId
        trafficAnalyticsInterval: 10
      }
    }
  }
}

output flowLogId string = flowLog.id
output flowLogName string = flowLog.name
