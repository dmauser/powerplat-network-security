@description('Resource ID of the east virtual network.')
param vnetEastId string

@description('Resource ID of the west virtual network.')
param vnetWestId string

@description('Tags applied to deployed resources.')
param tags object

var eastLinkName = 'link-east'
var westLinkName = 'link-west'

resource keyVaultZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
  tags: tags
}

resource keyVaultZoneEastLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: eastLinkName
  parent: keyVaultZone
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetEastId
    }
  }
}

resource keyVaultZoneWestLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: westLinkName
  parent: keyVaultZone
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetWestId
    }
  }
}

resource sqlZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  #disable-next-line no-hardcoded-env-urls
  name: 'privatelink.database.windows.net'
  location: 'global'
  tags: tags
}

resource sqlZoneEastLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: eastLinkName
  parent: sqlZone
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetEastId
    }
  }
}

resource sqlZoneWestLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: westLinkName
  parent: sqlZone
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetWestId
    }
  }
}

resource blobZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  #disable-next-line no-hardcoded-env-urls
  name: 'privatelink.blob.core.windows.net'
  location: 'global'
  tags: tags
}

resource blobZoneEastLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: eastLinkName
  parent: blobZone
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetEastId
    }
  }
}

resource blobZoneWestLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: westLinkName
  parent: blobZone
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetWestId
    }
  }
}

output kvZoneId string = keyVaultZone.id
output sqlZoneId string = sqlZone.id
output blobZoneId string = blobZone.id

// ---------------------------------------------------------------------------
// privatelink.azurewebsites.net — Function App inbound private endpoint
// ---------------------------------------------------------------------------
resource websitesZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  #disable-next-line no-hardcoded-env-urls
  name: 'privatelink.azurewebsites.net'
  location: 'global'
  tags: tags
}

resource websitesZoneEastLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: eastLinkName
  parent: websitesZone
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetEastId
    }
  }
}

resource websitesZoneWestLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: westLinkName
  parent: websitesZone
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetWestId
    }
  }
}

// ---------------------------------------------------------------------------
// privatelink.file.core.windows.net — Function App runtime storage file PE
// ---------------------------------------------------------------------------
resource fileZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  #disable-next-line no-hardcoded-env-urls
  name: 'privatelink.file.core.windows.net'
  location: 'global'
  tags: tags
}

resource fileZoneEastLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: eastLinkName
  parent: fileZone
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetEastId
    }
  }
}

resource fileZoneWestLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: westLinkName
  parent: fileZone
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetWestId
    }
  }
}

output websitesZoneId string = websitesZone.id
output fileZoneId string = fileZone.id
