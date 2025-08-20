@description('Location for DNS Resolver resources')
param location string
@description('Name of the existing virtual network to attach the resolver to')
param vnetName string
@description('Address prefix for the DNS Resolver inbound endpoint subnet (CIDR)')
param inboundSubnetPrefix string = '10.0.6.0/26'
@description('Resource group name for resolver child resources (defaults to deployment RG)')
param tags object = {}

// Create a dedicated subnet for DNS resolver endpoints
resource vnetExisting 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  name: vnetName
}

resource dnsSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  name: 'AzureDnsResolverSubnet'
  parent: vnetExisting
  properties: {
    addressPrefix: inboundSubnetPrefix
    delegations: [
      {
        name: 'dnsResolverDelegation'
        properties: {
          serviceName: 'Microsoft.Network/dnsResolvers'
        }
      }
    ]
  }
}

resource resolver 'Microsoft.Network/dnsResolvers@2022-07-01' = {
  name: '${vnetName}-dnsres'
  location: location
  properties: {
    virtualNetwork: {
      id: vnetExisting.id
    }
  }
  tags: tags
}

resource inbound 'Microsoft.Network/dnsResolvers/inboundEndpoints@2022-07-01' = {
  name: 'inbound'
  parent: resolver
  location: location
  properties: {
    ipConfigurations: [
      {
        subnet: {
          id: dnsSubnet.id
        }
      }
    ]
  }
}

output resolverId string = resolver.id
output inboundEndpointId string = inbound.id
output inboundSubnetId string = dnsSubnet.id
