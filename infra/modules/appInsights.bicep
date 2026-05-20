// =============================================================================
// Application Insights — workspace-based (Power Platform telemetry)
//
// This module provisions a workspace-based Application Insights resource
// linked to a Log Analytics workspace so that Power Platform (Managed
// Environment) telemetry lands in the same workspace as Azure resource
// diagnostics (Key Vault audit events, private-endpoint metrics, etc.).
//
// Microsoft Learn reference:
//   "Set up Application Insights for your environment" — Power Platform admin:
//   https://learn.microsoft.com/en-us/power-platform/admin/app-insights-overview
//
// Usage: linked from infra/main.bicep; depends on the logAnalytics module
// (Trinity) which exposes logAnalyticsWorkspaceId.
// =============================================================================

@description('Prefix used for all resource names.')
param prefix string

@description('Environment suffix used for resource names.')
param env string

@description('Azure region for this Application Insights resource.')
param location string

@description('Resource ID of the Log Analytics workspace to link. Provided by the logAnalytics module (Trinity). IngestionMode becomes LogAnalytics once this is set.')
param logAnalyticsWorkspaceId string

@description('Tags applied to the resource.')
param tags object = {}

// ---------------------------------------------------------------------------
// Resource
// ---------------------------------------------------------------------------

var appInsightsName = 'appi-${prefix}-${env}'

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  tags: tags
  properties: {
    // Application_Type must be 'web' for Power Platform integration.
    // See: https://learn.microsoft.com/en-us/power-platform/admin/app-insights-overview
    Application_Type: 'web'

    // Workspace-based mode: all telemetry is stored in the linked LAW,
    // enabling cross-resource KQL queries between PP requests and Azure
    // resource diagnostics (KV AuditEvent, PE metrics, etc.).
    WorkspaceResourceId: logAnalyticsWorkspaceId
    IngestionMode: 'LogAnalytics'

    // Network access: PP runtime sends telemetry over public ingestion endpoint.
    // Private link for App Insights ingestion requires additional PE config;
    // leave Enabled unless a dedicated AMPLS is in scope.
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ---------------------------------------------------------------------------
// Outputs — consumed by infra/main.bicep and scripts/02-configure-pp-vnet.ps1
// ---------------------------------------------------------------------------

@description('Name of the Application Insights resource.')
output appInsightsName string = appInsights.name

@description('Resource ID of the Application Insights resource.')
output appInsightsResourceId string = appInsights.id

@description('Connection string for the Application Insights resource (preferred over instrumentation key for new integrations).')
output appInsightsConnectionString string = appInsights.properties.ConnectionString

@description('Instrumentation key for the Application Insights resource (legacy; use connection string for new code).')
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
