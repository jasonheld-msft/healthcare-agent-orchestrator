// Azure Front Door Standard/Premium with Shared Private Link to App Service origin
// Creates:
// - AFD Profile
// - AFD Endpoint (default *.azureedge.net domain)
// - Origin Group
// - Origin pointing to App Service default hostname with Shared Private Link (groupId 'sites')
// - Route mapping /* to the origin group

param location string
param profileName string
param endpointName string
param originGroupName string = 'origin-group'
param originName string = 'webapp-origin'
@description('The default hostname of the App Service, e.g., <app>.azurewebsites.net')
param originHostName string
@description('Resource ID of the App Service origin')
param originResourceId string
param tags object = {}

// SKU: Standard_AzureFrontDoor or Premium_AzureFrontDoor
@allowed(['Standard_AzureFrontDoor', 'Premium_AzureFrontDoor'])
param skuName string = 'Standard_AzureFrontDoor'

resource profile 'Microsoft.Cdn/profiles@2024-09-01' = {
  name: profileName
  location: location
  sku: {
    name: skuName
  }
  tags: tags
}

resource endpoint 'Microsoft.Cdn/profiles/afdEndpoints@2024-09-01' = {
  name: endpointName
  parent: profile
  location: location
  properties: {
    enabledState: 'Enabled'
  }
  tags: tags
}

resource originGroup 'Microsoft.Cdn/profiles/originGroups@2024-09-01' = {
  name: originGroupName
  parent: profile
  properties: {
    sessionAffinityState: 'Disabled'
    healthProbeSettings: {
      probeIntervalInSeconds: 120
      probePath: '/'
      probeProtocol: 'Https'
      probeRequestType: 'HEAD'
    }
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 0
    }
  }
}

resource origin 'Microsoft.Cdn/profiles/originGroups/origins@2024-09-01' = {
  name: originName
  parent: originGroup
  properties: {
    hostName: originHostName
    httpsPort: 443
    originHostHeader: originHostName
    priority: 1
    weight: 1000
    enforceCertificateNameCheck: true
    // Shared Private Link to App Service origin
    sharedPrivateLinkResource: {
      groupId: 'sites'
      privateLink: {
        id: originResourceId
      }
      privateLinkLocation: location
      requestMessage: 'AFD to App Service private origin access'
    }
  }
}

resource routeDefault 'Microsoft.Cdn/profiles/afdEndpoints/routes@2024-09-01' = {
  name: 'route-all'
  parent: endpoint
  properties: {
    enabledState: 'Enabled'
    httpsRedirect: 'Enabled'
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    supportedProtocols: [ 'Https' ]
    originGroup: {
      id: originGroup.id
    }
    patternsToMatch: [ '/*' ]
  }
}

output frontDoorHostName string = endpoint.properties.hostName
output profileId string = profile.id
output endpointId string = endpoint.id
output originGroupId string = originGroup.id
output originId string = origin.id
