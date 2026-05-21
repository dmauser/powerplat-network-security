@description('Name of the network security perimeter resource.')
param nspName string

@description('Name of the NSP profile that owns the association.')
param profileName string

@description('Resource ID of the private-link-enabled target resource to associate.')
param targetResourceId string

@description('Name of the NSP resource association child resource.')
param associationName string

@description('NSP access mode. Use Learning for audit-only capture.')
@allowed([
  'Learning'
  'Audit'
  'Enforced'
])
param accessMode string = 'Learning'

resource nsp 'Microsoft.Network/networkSecurityPerimeters@2023-08-01-preview' existing = {
  name: nspName
}

resource profile 'Microsoft.Network/networkSecurityPerimeters/profiles@2023-08-01-preview' existing = {
  name: profileName
  parent: nsp
}

resource association 'Microsoft.Network/networkSecurityPerimeters/resourceAssociations@2023-11-01' = {
  name: associationName
  parent: nsp
  location: resourceGroup().location
  properties: {
    accessMode: accessMode
    privateLinkResource: {
      id: targetResourceId
    }
    profile: {
      id: profile.id
    }
  }
}

output associationId string = association.id
output associationName string = association.name
