# Network Security Architecture

Healthcare Agent Orchestrator implements a foundational network security architecture that can be enhanced to meet enterprise-grade security requirements for healthcare workloads. This document outlines the current implementation and provides guidance for implementing advanced security features including private App Service deployment with Application Gateway integration.

> [!IMPORTANT]
> The enhanced private architecture options described in this document are recommended for production healthcare environments handling PHI data. The current basic network implementation is suitable for development and testing scenarios.

## Current Network Implementation

The Healthcare Agent Orchestrator deploys with a secure network foundation that includes:

- **Virtual Network (VNet)** isolation with configurable address space (`10.0.0.0/16` default)
- **App Service subnet** with VNet integration (`10.0.1.0/24` default)
- **Service endpoints** for secure access to Azure Key Vault and Web services
- **Public storage accounts** with Azure services bypass for AI Hub and deployment compatibility
- **Network Security Groups (NSGs)** with HTTP/HTTPS inbound rules and Azure services/Internet outbound rules
- **App Service with IP restrictions** allowing access only from Microsoft 365/Teams IP ranges as defined in [Microsoft 365 URLs and IP address ranges](https://learn.microsoft.com/en-us/microsoft-365/enterprise/urls-and-ip-address-ranges?view=o365-worldwide#microsoft-teams) and any additional IPs specified in the `ADDITIONAL_ALLOWED_IPS` parameter set while deploying with azd

> [!NOTE]
> The App Service uses `ipSecurityRestrictionsDefaultAction: 'Deny'` for security. Access is restricted to Microsoft 365/Teams IP ranges and any additional IPs you specify. To add your own IP for development access, use the `ADDITIONAL_ALLOWED_IPS` environment variable during deployment.

### Adding Developer Access

To allow additional IP addresses (such as your development machine) to access the App Service, you can set the `ADDITIONAL_ALLOWED_IPS` environment variable:

```bash
# For a single IP address
azd env set ADDITIONAL_ALLOWED_IPS "203.0.113.100/32"

# For multiple IP addresses or ranges (comma-separated)
azd env set ADDITIONAL_ALLOWED_IPS "203.0.113.100/32,198.51.100.0/24,192.168.1.0/24"

# To remove all additional IPs (only Microsoft 365/Teams ranges will be allowed)
azd env set ADDITIONAL_ALLOWED_IPS ""

# Then redeploy
azd up
```

### Microsoft 365/Teams Integration Considerations

- **IP Restriction Limitations**: The current IP-based approach covers core Teams/M365 services but has limitations with FQDN-dependent services (like `*.teams.microsoft.com`, `login.microsoft.com`). For full functionality, consider Azure Firewall with FQDN rules or the enhanced private architecture with Application Gateway.

### Security Features

- **Network Isolation**: Resources deployed within dedicated virtual network
- **Subnet Delegation**: App Service subnet specifically configured for web applications
- **Service Endpoints**: Secure connectivity to Azure PaaS services without internet routing
- **Traffic Control**: NSG rules for granular inbound and outbound traffic management

### Network Configuration Parameters

The network architecture is fully parameterized and can be customized during deployment. Organizations can modify the following parameters in `main.parameters.json` or set the corresponding environment variables before running `azd up`:

**VNet Configuration**:
- `vnetName`: Custom name for the virtual network (auto-generated if not specified)
- `vnetAddressPrefixes`: Array of address prefixes for the VNet (default: `["10.0.0.0/16"]`)
- `networkLocation`: Azure region for network resources should be similar to that as the appservice (defaults to resource group location)

**Subnet Configuration**:
- `subnets`: Array of subnet configurations, each containing:
  - `name`: Subnet name (default: `"appservice-subnet"`)
  - `addressPrefix`: Subnet address range (default: `"10.0.1.0/24"`)
  - `delegation`: Service delegation (default: `"Microsoft.Web/serverFarms"`)
  - `serviceEndpoints`: Array of service endpoint objects with `service` and `locations` properties
  - `securityRules`: Custom NSG rules for the subnet

**Environment Variables**: Set `AZURE_VNET_NAME`, `VNET_ADDRESS_PREFIXES`, and `APPSERVICE_SUBNET_PREFIX` to customize network configuration.

**Example Parameter Override for main.parameters.json**:
```json
"vnetName": {
  "value": "${AZURE_VNET_NAME}"
},
"vnetAddressPrefixes": {
  "value": ["${VNET_ADDRESS_PREFIXES}"]
},
"subnets": {
  "value": [
    {
      "name": "appservice-subnet",
      "addressPrefix": "${APPSERVICE_SUBNET_PREFIX}",
      "delegation": "Microsoft.Web/serverFarms",
      "serviceEndpoints": [
        {
          "service": "Microsoft.Web",
          "locations": ["*"]
        },
        {
          "service": "Microsoft.KeyVault",
          "locations": ["*"]
        },
        {
          "service": "Microsoft.Storage",
          "locations": ["*"]
        }
      ],
      "securityRules": []
    }
  ]
}
```

> [!NOTE]
> Copy and paste the above JSON directly into your `main.parameters.json` file to enable network customization via environment variables.

> [!TIP]
> Organizations should choose non-overlapping address spaces that align with their existing network infrastructure. The default `10.0.0.0/16` range can be modified to avoid conflicts with on-premises networks or other Azure VNets.

## Enhanced Private Architecture Options

For production healthcare environments, organizations may consider upgrading to enterprise-grade security through several architecture enhancements. The following options provide examples of how the current network foundation can be extended to meet more stringent security requirements.

### Example: Private App Service with Application Gateway

**Current Implementation**: App Service is accessible only from Microsoft 365/Teams IP ranges
**Potential Enhancement**: App Service could be made private, accessible only through Application Gateway

**Benefits**:
- Web Application Firewall (WAF) protection against OWASP Top 10 vulnerabilities
- Centralized SSL/TLS termination and certificate management
- Load balancing and traffic distribution capabilities
- Elimination of direct internet access to backend services

> [!NOTE]
> When implementing private App Service deployment, organizations must consider secure developer access methods since direct internet access to the App Service will no longer be available. Common approaches include VPN Gateway (Point-to-Site) with certificate-based authentication, Azure Bastion for browser-based secure access, or private build agents for CI/CD pipeline execution within the VNet.

### Example: Private Endpoints Integration

**Current Implementation**: Service endpoints route traffic over Azure backbone, but services remain publicly accessible
**Potential Enhancement**: Azure services could be accessible via private IP addresses within the VNet

**Benefits**:
- Complete network isolation for all Azure PaaS services
- No internet exposure for Key Vault, Storage, and Cognitive Services
- Private DNS integration for seamless connectivity
- Enhanced compliance with healthcare data protection requirements


### Architecture Components Overview

The following sections outline the key network components and configurations that organizations may need when implementing the enhanced private architecture for their healthcare workloads.

#### Application Gateway Configuration

**Subnet Requirements**:
- Address prefix: `10.0.2.0/24`
- Dedicated subnet for Application Gateway deployment
- No delegation required
- Specific NSG rules for Application Gateway traffic
- Private DNS Zones: Configure  `privatelink.azurewebsites.net` and related zones for private endpoint and vpn name resolution
- Backed Pool Targets: use private endpoint ip's. 

**SSL/TLS Configuration**:
- Frontend HTTPS endpoint with public-facing access
- Backend communication secured between Application Gateway and App Service
- Certificate management integrated with Azure Key Vault

#### Private Endpoints Subnet Configuration

**Subnet Setup**:
- Address prefix: `10.0.3.0/24`
- Dedicated subnet for private endpoint network interfaces
- Network policies configured to support private endpoint deployments

**Private DNS Zones Configuration**:
- Key Vault: `privatelink.vaultcore.azure.net`
- Storage: `privatelink.blob.core.windows.net`
- Cognitive Services: `privatelink.cognitiveservices.azure.com`

#### Developer Access Considerations for Private App Service

When implementing private App Service deployment, organizations must establish secure access methods for development and maintenance activities. The following options address the connectivity requirements:

**VPN Gateway (Point-to-Site)**:
- Subnet: `10.0.4.0/26` (GatewaySubnet)
- Certificate-based authentication
- Point-to-site VPN configuration
- Enables secure remote access for development teams

**Azure Bastion**:
- Subnet: `10.0.5.0/26` (AzureBastionSubnet)
- Browser-based secure access
- Managed jump box service
- No client software installation required
- Access to virtual machines within the VNet for administrative tasks

### Cost Considerations

The enhanced private architecture incurs additional costs for Application Gateway, VPN Gateway, Private Endpoints, and related infrastructure components.

### Implementation Considerations

Organizations may want to consider the following prerequisites when planning enhanced private architecture implementation:

- Azure subscription with appropriate permissions for network resource creation
- SSL certificates for Application Gateway (can be managed through Azure Key Vault)
- Root CA certificate for VPN Gateway setup (if choosing VPN option)
- Updated CI/CD pipelines to support private build agents or secure deployment methods

### Developer Workflow Considerations

**Potential Impact**: Private App Service deployment would change developer access patterns
**Example Mitigation Strategies**:
- Implementing automated CI/CD pipelines to reduce manual access requirements
- Providing VPN access for necessary debugging and troubleshooting
- Using Azure Bastion for secure administrative access
- Establishing clear procedures for emergency access scenarios


> [!WARNING]
> Implementing private App Service deployment would require changes to developer workflows and CI/CD pipelines. Organizations should plan accordingly and ensure proper access methods are configured before disabling public access.

## Next Steps

For detailed implementation guidance, refer to the following resources:

- [Azure Application Gateway documentation](https://docs.microsoft.com/azure/application-gateway/)
- [Private App Service deployment guide](https://docs.microsoft.com/azure/app-service/networking/private-endpoint)
- [Azure Private Endpoints configuration](https://docs.microsoft.com/azure/private-link/private-endpoint-overview)
- [VPN Gateway setup instructions](https://docs.microsoft.com/azure/vpn-gateway/)

The example enhanced private architecture provides a potential foundation for healthcare application hosting in Azure while maintaining compliance with industry standards and regulations.

## Using private connectivity and P2S VPN

This project supports two switches that harden network access and enable private developer connectivity:

- ENABLE_PRIVATE_CONNECTIVITY: Locks down platform services behind Private Endpoints and Private DNS.
- deployP2SVpn: (Optional) Provisions a Point‑to‑Site (P2S) VPN Gateway so developers can securely reach private resources from their machines.

### What ENABLE_PRIVATE_CONNECTIVITY does

When set to true, the deployment:

- Creates a dedicated `private-endpoints` subnet and Private Endpoints for:
  - Storage (blob)
  - Key Vault
  - Cognitive Services (AI Services)
  - App Service (sites)
  - FHIR (only if the template deploys FHIR)
- Creates and links Private DNS zones to the VNet:
  - privatelink.blob.core.windows.net
  - privatelink.vaultcore.azure.net
  - privatelink.cognitiveservices.azure.com
  - privatelink.fhir.azurehealthcareapis.com (if used)
  - privatelink.azurewebsites.net
- Disables public network access on Storage, Key Vault, and Cognitive Services.
- App Service becomes reachable via its Private Endpoint (privatelink) instead of public internet.

Enable with azd:

```bash
azd env set ENABLE_PRIVATE_CONNECTIVITY true
azd up
```

Alternatively, set in `infra/main.parameters.json`:

```json
"enablePrivateConnectivity": {
  "value": true
}
```

### Optional: Enable P2S VPN for developer access

If you don’t have an existing corporate VPN and need local access to private resources (App Service, Key Vault, Storage, AI Services, FHIR), enable the built‑in P2S VPN Gateway:

1. Provide a root certificate (certificate auth)

On macOS you can generate a root cert and export a Base64 public cert:

```bash
# Generate a root key and self‑signed root certificate (valid 10 years)
openssl genrsa -out rootCA.key 4096
openssl req -x509 -new -nodes -key rootCA.key -sha256 -days 3650 -out rootCA.crt -subj "/CN=Healthcare Orchestrator VPN Root"

# Export a DER‑encoded .cer (public cert), then Base64 encode its contents
openssl x509 -in rootCA.crt -outform der -out rootCA.cer
BASE64_CERT=$(openssl base64 -A -in rootCA.cer)
```

1. Set the VPN parameters and deploy

```bash
azd env set deployP2SVpn true
azd env set vpnRootCertName "HealthcareOrchestratorRoot"
azd env set vpnRootCertData "$BASE64_CERT"

# Optional: adjust gateway SKU and client address pool
azd env set vpnGatewaySku VpnGw1
azd env set vpnClientAddressPool 172.16.0.0/24

azd up
```

Provisioning a VPN gateway typically takes 30–45 minutes.

1. Create a client certificate for your user (sign with the root) and import into your macOS Keychain, then use OpenVPN/Tunnelblick with the client profile to connect. See Azure P2S OpenVPN documentation for generating the client profile and importing the cert.

```bash
openssl genrsa -out client-vpn.key 4096
openssl req -new -key client-vpn.key -out client-vpn.csr -subj "/CN=$(whoami)"

openssl x509 -req -in client-vpn.csr -CA rootCA.crt -CAkey rootCA.key -CAcreateserial -out client-vpn.crt -days 365 -sha256
```

### Optional: DNS Private Resolver (toggle via deployDnsResolver)

For P2S clients to resolve privatelink hostnames over the VPN without host file hacks, deploy the Azure DNS Private Resolver. This module is included in the Bicep but is gated by the deployDnsResolver parameter (default: false).

Enable with azd:

```bash
azd env set deployDnsResolver true
azd up
```

Verify resources:

```bash
az network dns-resolver list -g rg-hco-no-radiology -o table
az network dns-resolver inbound-endpoint list -g rg-hco-no-radiology -o table
```

Use the inbound endpoint IP in your OpenVPN/Tunnelblick profile via `dhcp-option DNS <ip>` and add DOMAIN-ROUTE entries for privatelink zones (see the client DNS configuration section below).

### DNS for Private Endpoints (important)

To resolve privatelink hostnames from your machine over VPN, configure DNS:

- Preferred: Use Azure DNS Private Resolver or a custom DNS VM in the VNet. Configure your VPN to hand out that DNS server and set conditional forwarders for:
  - privatelink.azurewebsites.net
  - privatelink.blob.core.windows.net
  - privatelink.vaultcore.azure.net
  - privatelink.cognitiveservices.azure.com
  - privatelink.fhir.azurehealthcareapis.com (if used)
- Temporary workaround: Map your app host to its Private Endpoint IP in `/etc/hosts` for quick testing. Prefer DNS for ongoing work.

### Verifying private connectivity

After deployment (and VPN + DNS setup):

- DNS
  - `nslookup <yourapp>.azurewebsites.net` should CNAME to `privatelink.azurewebsites.net` and resolve to a 10.x IP.
  - `nslookup <storage>.blob.core.windows.net` should return a privatelink A record (10.x).
- App Service
  - `curl -I https://<yourapp>.azurewebsites.net` should succeed over the private path.
- SDK/CLI
  - Azure SDK/CLI calls to Key Vault, Storage, Cognitive Services should succeed only when connected to the VPN/private network.

### Useful deployment outputs

The deployment emits helpful outputs to validate and integrate networking:

- Private DNS zones:
  - `PRIVATE_DNS_BLOB_ZONE`, `PRIVATE_DNS_KEYVAULT_ZONE`, `PRIVATE_DNS_COGSERV_ZONE`, `PRIVATE_DNS_FHIR_ZONE`, `PRIVATE_DNS_WEBSITES_ZONE`
- Private Endpoint IDs:
  - `PE_STORAGE_ID`, `PE_KEYVAULT_ID`, `PE_COGSERV_ID`, `PE_FHIR_ID`, `PE_WEBSITES_ID`
- VNet and subnets:
  - `VNET_ID`, `APP_SERVICE_SUBNET_ID`, and when VPN is enabled: `GATEWAY_SUBNET_ID`
- VPN gateway (when enabled):
  - `VPN_GATEWAY_ID`, `VPN_GATEWAY_PUBLIC_IP_ID`, `VPN_CLIENT_ADDRESS_POOL`

You can view outputs in the azd deployment logs or in the Azure Portal under the deployment record for the resource group.

### Troubleshooting

- Timeouts/403 to private services: Ensure the VPN is connected and DNS resolves to 10.x addresses.
- App Service not reachable publicly: With App Service PE enabled, use VPN or front it with Application Gateway/Front Door.
- DNS doesn’t resolve: Add a DNS forwarder (Azure DNS Private Resolver or custom DNS VM) and configure your VPN to use it; avoid relying on `/etc/hosts` long‑term.
