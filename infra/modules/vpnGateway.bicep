@description('Location for VPN resources')
param location string
@description('Name of the existing virtual network to attach the gateway to')
param vnetName string
@description('Address prefix for the GatewaySubnet (CIDR)')
param gatewaySubnetPrefix string = '10.0.4.0/26'
@description('SKU for the VPN gateway (VpnGw1..5)')
@allowed(['VpnGw1','VpnGw2','VpnGw3','VpnGw4','VpnGw5'])
param vpnGatewaySku string = 'VpnGw1'
@description('Client address pool for P2S VPN (CIDR)')
param vpnClientAddressPool string = '172.16.0.0/24'
@description('Optional: Name of the root certificate for P2S certificate authentication')
param vpnRootCertName string = ''
@description('Optional: Base64-encoded public certificate data for P2S root certificate')
param vpnRootCertData string = ''
param tags object = {}

resource vnetExisting 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  name: vnetName
}

resource gwSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  name: 'GatewaySubnet'
  parent: vnetExisting
  properties: {
    addressPrefix: gatewaySubnetPrefix
  }
}

resource vpnPip 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: '${vnetName}-vpngw-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
  tags: tags
}

resource vpngw 'Microsoft.Network/virtualNetworkGateways@2023-09-01' = {
  name: '${vnetName}-vpngw'
  location: location
  properties: {
    enableBgp: false
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    activeActive: false
    sku: {
      name: vpnGatewaySku
      tier: vpnGatewaySku
    }
    ipConfigurations: [
      {
        name: 'vnetGatewayConfig'
        properties: {
          publicIPAddress: {
            id: vpnPip.id
          }
          subnet: {
            id: '${vnetExisting.id}/subnets/GatewaySubnet'
          }
        }
      }
    ]
    vpnClientConfiguration: {
      vpnClientAddressPool: {
        addressPrefixes: [ vpnClientAddressPool ]
      }
      vpnClientProtocols: [ 'OpenVPN' ]
      vpnClientRootCertificates: empty(vpnRootCertName) || empty(vpnRootCertData) ? [] : [
        {
          name: vpnRootCertName
          properties: {
            publicCertData: vpnRootCertData
          }
        }
      ]
    }
  }
  tags: tags
}

output vpnGatewayId string = vpngw.id
output vpnPublicIpId string = vpnPip.id
output gatewaySubnetId string = '${vnetExisting.id}/subnets/GatewaySubnet'
output vpnClientAddressPool string = vpnClientAddressPool
