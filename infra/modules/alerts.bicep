// alerts.bicep
// Azure Monitor alerts for the Key Vault private-endpoint observability story.
//
// Design philosophy: opt-in by default (enableAlerts = false).
// The action group is ALWAYS created so dmauser can wire notification targets
// (email, webhook, ITSM) at any time without re-deploying. Alerts are conditional
// on enableAlerts to prevent email spam in lab environments.
//
// Alert inventory:
//   1. KV public-endpoint denial spike  — log-search alert (KQL on AzureDiagnostics)
//   2. KV availability drop             — metric alert on Availability < 99%
//   3. PE health degraded               — metric alert for each of the 3 private endpoints

@description('Prefix used for all resource names.')
param prefix string

@description('Environment suffix used for resource names.')
param env string

@description('Azure location for scheduled query rule resources. Must match the LAW region.')
param location string

@description('Tags applied to deployed resources.')
param tags object

@description('Resource ID of the Log Analytics workspace (required for log-search alert scope).')
param workspaceId string

@description('Resource ID of the Key Vault (required for KV availability metric alert).')
param keyVaultId string

@description('Resource ID of the Key Vault private endpoint.')
param kvPeId string

@description('Resource ID of the SQL private endpoint. Pass empty string to skip PE alert.')
param sqlPeId string = ''

@description('Resource ID of the Storage/blob private endpoint. Pass empty string to skip PE alert.')
param blobPeId string = ''

@description('Enable alert rules. When false only the action group stub is deployed.')
param enableAlerts bool = false

// ─── Action group ────────────────────────────────────────────────────────────
// Always deployed so notification targets can be wired without re-running IaC.
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-${prefix}-${env}-observability'
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: 'obs-ag'
    enabled: true
    emailReceivers:   []
    smsReceivers:     []
    webhookReceivers: []
  }
}

// ─── Alert 1: KV public-endpoint denial spike (log-search) ───────────────────
// Watches AzureDiagnostics for Key Vault vault/secret operations that return
// Denied or Forbidden — the signal that something tried the public endpoint
// while publicNetworkAccess=Disabled is in effect.
resource kvDenialAlert 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = if (enableAlerts) {
  name: 'alert-kv-public-denial-${prefix}-${env}'
  location: location
  tags: tags
  properties: {
    description: 'Fires when KV vault/secret operations are Denied or Forbidden >5 times in 5 min — possible public-endpoint access attempt or misconfigured connector.'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    scopes: [workspaceId]
    criteria: {
      allOf: [
        {
          query: '''AzureDiagnostics
| where ResourceType == "VAULTS"
| where OperationName in ("VaultGet", "SecretGet")
| where ResultType contains "Denied" or ResultType contains "Forbidden"'''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 5
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroup.id]
    }
    autoMitigate: false
  }
}

// ─── Alert 2: KV availability drop (metric) ──────────────────────────────────
resource kvAvailabilityAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableAlerts) {
  name: 'alert-kv-availability-${prefix}-${env}'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Fires when Key Vault Availability drops below 99% over a 15-minute window.'
    severity: 1
    enabled: true
    scopes: [keyVaultId]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          name: 'availability-below-99'
          metricName: 'Availability'
          metricNamespace: 'Microsoft.KeyVault/vaults'
          operator: 'LessThan'
          threshold: 99
          timeAggregation: 'Average'
        }
      ]
    }
    actions: [
      { actionGroupId: actionGroup.id }
    ]
  }
}

// ─── Alert 3: PE health degraded — KV private endpoint ───────────────────────
// PEHealthStatus = 1 (healthy). Alert when the metric drops below 1.
// Note: PEHealthStatus is an Azure Monitor metric for Microsoft.Network/privateEndpoints.
// If not available in your region/tier, substitute PEBytesIn with threshold 0.
resource kvPeHealthAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableAlerts) {
  name: 'alert-pe-kv-health-${prefix}-${env}'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Fires when the Key Vault private endpoint health status is not healthy (PEHealthStatus < 1).'
    severity: 2
    enabled: true
    scopes: [kvPeId]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          name: 'pe-health-degraded'
          metricName: 'PEConnectionsConnected'
          metricNamespace: 'Microsoft.Network/privateEndpoints'
          operator: 'LessThan'
          threshold: 1
          timeAggregation: 'Average'
        }
      ]
    }
    actions: [
      { actionGroupId: actionGroup.id }
    ]
  }
}

// ─── Alert 4: PE health degraded — SQL private endpoint ──────────────────────
resource sqlPeHealthAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableAlerts && !empty(sqlPeId)) {
  name: 'alert-pe-sql-health-${prefix}-${env}'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Fires when the SQL private endpoint health status is not healthy (PEConnectionsConnected < 1).'
    severity: 2
    enabled: true
    scopes: [sqlPeId]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          name: 'pe-health-degraded'
          metricName: 'PEConnectionsConnected'
          metricNamespace: 'Microsoft.Network/privateEndpoints'
          operator: 'LessThan'
          threshold: 1
          timeAggregation: 'Average'
        }
      ]
    }
    actions: [
      { actionGroupId: actionGroup.id }
    ]
  }
}

// ─── Alert 5: PE health degraded — Storage/blob private endpoint ──────────────
resource blobPeHealthAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableAlerts && !empty(blobPeId)) {
  name: 'alert-pe-blob-health-${prefix}-${env}'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Fires when the Storage/blob private endpoint health status is not healthy (PEConnectionsConnected < 1).'
    severity: 2
    enabled: true
    scopes: [blobPeId]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          name: 'pe-health-degraded'
          metricName: 'PEConnectionsConnected'
          metricNamespace: 'Microsoft.Network/privateEndpoints'
          operator: 'LessThan'
          threshold: 1
          timeAggregation: 'Average'
        }
      ]
    }
    actions: [
      { actionGroupId: actionGroup.id }
    ]
  }
}

output actionGroupId string = actionGroup.id
