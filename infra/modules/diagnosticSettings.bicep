// diagnosticSettings.bicep
// Reusable module that attaches a Microsoft.Insights/diagnosticSettings resource to any
// Azure target resource, identified by its full resource ID.
//
// Bicep limitation: extension-resource scopes must be statically-typed resource references.
// This module works around that constraint by embedding the diagnostic-settings resource
// inside an inline ARM nested deployment, where ARM supports dynamic scope strings.
// The nested deployment uses expressionEvaluationOptions.scope=inner so all expressions
// are resolved within the nested template context.
//
// Caller shape (from main.bicep):
//   module kvDiag 'modules/diagnosticSettings.bicep' = {
//     scope: rg
//     params: {
//       targetResourceId: keyVault.outputs.keyVaultId
//       workspaceId:      logAnalytics.outputs.workspaceId
//       settingName:      'diag-kv'
//       logs:    [ { category: 'AuditEvent', enabled: true } ]
//       metrics: [ { category: 'AllMetrics', enabled: true } ]
//     }
//   }

@description('Full resource ID of the target resource to configure diagnostics for.')
param targetResourceId string

@description('Resource ID of the Log Analytics workspace to receive diagnostic data.')
param workspaceId string

@description('Name of the diagnostic setting resource. Must be unique per target resource.')
param settingName string = 'default-diagnostics'

@description('Log categories to enable. Each item: { category: string, enabled: bool }')
param logs array = []

@description('Metric categories to enable. Each item: { category: string, enabled: bool }')
param metrics array = []

// Nested ARM deployment so the diagnostic setting can be created for an arbitrary
// resource type without Bicep needing to know the type at compile time.
// The no-deployments-resources lint rule is suppressed here because this is the
// only Bicep-native pattern for attaching an extension resource (diagnosticSettings)
// to a dynamically-scoped target without statically declaring the target's resource type.
#disable-next-line no-deployments-resources
resource innerDeployment 'Microsoft.Resources/deployments@2022-09-01' = {
  name: 'diag-${uniqueString(targetResourceId, settingName)}'
  properties: {
    mode: 'Incremental'
    expressionEvaluationOptions: {
      scope: 'inner'
    }
    parameters: {
      targetResourceId: { value: targetResourceId }
      workspaceId:      { value: workspaceId }
      settingName:      { value: settingName }
      logs:             { value: logs }
      metrics:          { value: metrics }
    }
    template: {
      '$schema': 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        targetResourceId: { type: 'string' }
        workspaceId:      { type: 'string' }
        settingName:      { type: 'string' }
        logs:             { type: 'array' }
        metrics:          { type: 'array' }
      }
      resources: [
        {
          type: 'Microsoft.Insights/diagnosticSettings'
          apiVersion: '2021-05-01-preview'
          // scope accepts a full resource ID string in ARM JSON — evaluated at deploy time.
          scope: '[parameters(\'targetResourceId\')]'
          name:  '[parameters(\'settingName\')]'
          properties: {
            workspaceId: '[parameters(\'workspaceId\')]'
            logs:        '[parameters(\'logs\')]'
            metrics:     '[parameters(\'metrics\')]'
          }
        }
      ]
    }
  }
}
