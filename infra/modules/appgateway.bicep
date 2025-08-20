@description('Location for Application Gateway')
param location string
@description('Name of the Application Gateway')
param appGatewayName string
@description('VNet ID where the Application Gateway will be deployed')
param vnetId string
@description('Subnet name within the VNet for the Application Gateway (no delegation required)')
param subnetName string
@description('Backend host name (App Service default host), e.g., <app>.azurewebsites.net')
param backendHostName string
@description('DNS label for the public IP (creates <label>.<region>.cloudapp.azure.com)')
param publicDnsLabel string
@description('Optional Key Vault secret ID of a PFX certificate for HTTPS listener; if empty, HTTP (80) listener is used')
@secure()
param keyVaultCertSecretId string
@description('Path used by the health probe; default is "/". You can set this to a health endpoint or your bot route like /api/{bot}/messages')
param probePath string = '/'
@description('Tags to apply')
param tags object = {}

var pipName = '${appGatewayName}-pip'
var frontendIpName = 'appGatewayFrontendIP'
var frontendPort80Name = 'port80'
var frontendPort443Name = 'port443'
var gatewayIpConfigName = 'appGatewayIpConfig'
var backendPoolName = 'appBackendPool'
var backendHttpSettingsName = 'httpsSettings'
var probeName = 'defaultProbe'
var listenerName = 'appGatewayListener'
var routingRuleName = 'rule1'
var useHttps = !empty(keyVaultCertSecretId)

resource pip 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: pipName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: publicDnsLabel
    }
  }
  tags: tags
}

resource appGw 'Microsoft.Network/applicationGateways@2024-05-01' = {
  name: appGatewayName
  location: location
  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
    }
    enableHttp2: true
    autoscaleConfiguration: {
      minCapacity: 1
    }
    gatewayIPConfigurations: [
      {
        name: gatewayIpConfigName
        properties: {
          subnet: {
            id: '${vnetId}/subnets/${subnetName}'
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: frontendIpName
        properties: {
          publicIPAddress: {
            id: pip.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: frontendPort80Name
        properties: {
          port: 80
        }
      }
      {
        name: frontendPort443Name
        properties: {
          port: 443
        }
      }
    ]
    sslCertificates: useHttps ? [
      {
        name: 'sslCert'
        properties: {
          keyVaultSecretId: keyVaultCertSecretId
        }
      }
    ] : []
    probes: [
      {
        name: probeName
        properties: {
          protocol: useHttps ? 'Https' : 'Http'
          path: probePath
          interval: 30
          timeout: 30
          unhealthyThreshold: 3
          pickHostNameFromBackendHttpSettings: true
        }
      }
    ]
    backendAddressPools: [
      {
        name: backendPoolName
        properties: {
          backendAddresses: [
            {
              fqdn: backendHostName
            }
          ]
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: backendHttpSettingsName
        properties: {
          protocol: useHttps ? 'Https' : 'Http'
          port: useHttps ? 443 : 80
          pickHostNameFromBackendAddress: true
          requestTimeout: 60
          probe: {
            id: resourceId('Microsoft.Network/applicationGateways/probes', appGatewayName, probeName)
          }
        }
      }
    ]
    httpListeners: [
      {
        name: listenerName
        properties: union(
          {
            frontendIPConfiguration: {
              id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appGatewayName, frontendIpName)
            }
            frontendPort: {
              id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGatewayName, useHttps ? frontendPort443Name : frontendPort80Name)
            }
            protocol: useHttps ? 'Https' : 'Http'
            requireServerNameIndication: useHttps
            hostName: ''
          },
          useHttps ? {
            sslCertificate: {
              id: resourceId('Microsoft.Network/applicationGateways/sslCertificates', appGatewayName, 'sslCert')
            }
          } : {}
        )
      }
    ]
    requestRoutingRules: [
      {
        name: routingRuleName
        properties: {
          ruleType: 'Basic'
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGatewayName, listenerName)
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGatewayName, backendPoolName)
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGatewayName, backendHttpSettingsName)
          }
          priority: 100
        }
      }
    ]
    webApplicationFirewallConfiguration: {
      enabled: true
      firewallMode: 'Detection'
      ruleSetType: 'OWASP'
      ruleSetVersion: '3.2'
      requestBodyCheck: true
    }
  }
  tags: tags
}

output publicFqdn string = pip.properties.dnsSettings.fqdn
