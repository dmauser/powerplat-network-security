@description('Prefix used for all resource names.')
param prefix string

@description('Environment suffix used for resource names.')
param env string

@description('Azure location for the network security perimeter deployment.')
param location string

@description('Tags applied to deployed resources.')
param tags object

@description('Optional. Resource ID of the Log Analytics workspace for NSP diagnostic settings. Leave empty to skip.')
param logAnalyticsWorkspaceId string = ''

var nspName = 'nsp-${prefix}-${env}'
var nspProfileName = 'nsp-profile-${prefix}-${env}'

resource nsp 'Microsoft.Network/networkSecurityPerimeters@2023-08-01-preview' = {
  name: nspName
  location: location
  tags: tags
  properties: {}
}

resource nspProfile 'Microsoft.Network/networkSecurityPerimeters/profiles@2023-08-01-preview' = {
  name: nspProfileName
  parent: nsp
  location: location
  properties: {}
}

resource nspDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: 'diag-nsp'
  scope: nsp
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      { category: 'NspPublicInboundPerimeterRulesAllowed',  enabled: true }
      { category: 'NspPublicInboundPerimeterRulesDenied',   enabled: true }
      { category: 'NspPublicOutboundPerimeterRulesAllowed', enabled: true }
      { category: 'NspPublicOutboundPerimeterRulesDenied',  enabled: true }
      { category: 'NspPrivateInboundAllowed',               enabled: true }
      { category: 'NspIntraPerimeterInboundAllowed',        enabled: true }
      { category: 'NspCrossPerimeterInboundAllowed',        enabled: true }
      { category: 'NspCrossPerimeterOutboundAllowed',       enabled: true }
      { category: 'NspOutboundAttempt',                     enabled: true }
      { category: 'NspPublicInboundResourceRulesAllowed',   enabled: true }
      { category: 'NspPublicInboundResourceRulesDenied',    enabled: true }
      { category: 'NspPublicOutboundResourceRulesAllowed',  enabled: true }
      { category: 'NspPublicOutboundResourceRulesDenied',   enabled: true }
    ]
  }
}

output nspId string = nsp.id
output nspName string = nsp.name
output nspProfileId string = nspProfile.id
output nspProfileName string = nspProfile.name
