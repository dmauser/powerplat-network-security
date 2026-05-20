@description('Prefix used for all resource names.')
param prefix string

@description('Environment suffix used for resource names.')
param env string

@description('Azure location for the managed identity.')
param location string

@description('Tags applied to deployed resources.')
param tags object

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'uami-${prefix}-${env}'
  location: location
  tags: tags
}

output userAssignedIdentityName string = userAssignedIdentity.name
output userAssignedIdentityResourceId string = userAssignedIdentity.id
output userAssignedIdentityPrincipalId string = userAssignedIdentity.properties.principalId
output userAssignedIdentityClientId string = userAssignedIdentity.properties.clientId
