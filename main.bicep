//storageAccount Param
@minLength(3)
@maxLength(24)
@description('Provide a name for the storage account. Use only lower case letters and numbers. The name must be unique across Azure.')
param storageAccountName string
param location string = resourceGroup().location
param storageAccount_sku_size string


// VNET param
param vnet_name string
param vnet_addr_prefix string
param subnet_name array
param subnet_addr_prefixes array

param logic_subnetNSG string

// APPGW param and variable
param applicationGatewayName string
param appGwSize string
param minCapacity int
param maxCapacity int
param frontendPort int
param backendPort int
param cookieBasedAffinity string
param backendIPAddresses array = [
    {
      IpAddress: 'api.contoso.net'
    }
    {
      FQDN: 'portal.contoso.net'
    }
    {
      IpAddress: '10.0.1.15'
    }
]

var appGwPublicIpName = '${applicationGatewayName}-pip'


//ASE param
param aseName string
// @allowed([
//   'None'
//   'Publishing'
//   'Web'
//   'Web,Publishing'
// ])
param internalLoadBalancingMode string

param websiteName string
param appServicePlanName string
param numberOfWorkers int

@allowed([
  '1'
  '2'
  '3'
])
param workerPool string



//Virtual network and subnet
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2019-11-01' = {
  name: vnet_name
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnet_addr_prefix
      ]
    }
    subnets: [
      {
        name: subnet_name[0]
        properties: {
          addressPrefix: subnet_addr_prefixes[0]
        }
      }
      {
        name: subnet_name[1]
        properties: {
          addressPrefix: subnet_addr_prefixes[1]
          networkSecurityGroup: logicsubnetNSG.id == '' ? null : {
            id: logicsubnetNSG.id
          }

        }
      }
      {
        name: subnet_name[2]
        properties: {
          addressPrefix: subnet_addr_prefixes[2]
          
        }
      }
    ]
  }
}


//Storage Account
resource exampleStorage 'Microsoft.Storage/storageAccounts@2021-08-01'= {
  name: storageAccountName
  location: location
  sku: {
    name: storageAccount_sku_size
  }
  kind: 'StorageV2'
}

// AppGW NSG
resource logicsubnetNSG 'Microsoft.Network/networkSecurityGroups@2021-05-01'= {
  name: logic_subnetNSG
  location: location
  properties: {
    securityRules: [
      {
        id: logic_subnetNSG
        name: 'bicep-vnet'
        properties: {
          access: 'Allow'
          description: 'Vnet access granted'
          destinationAddressPrefix: vnet_addr_prefix
          destinationPortRange: '*'
          direction: 'Inbound'
          priority: 100
          protocol: '*'
          sourceAddressPrefix: vnet_addr_prefix
          sourcePortRange: '*'
        }

      }
    ]
  }
}

// Applicationgateway Public IP
resource publicIP 'Microsoft.Network/publicIPAddresses@2021-05-01' = {
  name: appGwPublicIpName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}


// Application Gateway
resource applicationGateway 'Microsoft.Network/applicationGateways@2021-05-01' = {
  name: applicationGatewayName
  location: location
  properties: {
    sku: {
      name: appGwSize
      tier: 'Standard_v2'
    }
    autoscaleConfiguration: {
      minCapacity: minCapacity
      maxCapacity: maxCapacity
    }
    gatewayIPConfigurations: [
      {
        name: 'appGatewayIpConfig'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetwork.name, subnet_name[2])
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appGatewayFrontendIP'
        properties: {
          publicIPAddress: {
            id: publicIP.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'appGatewayFrontendPort'
        properties: {
          port: frontendPort
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'appGatewayBackendPool'
        properties: {
          backendAddresses: backendIPAddresses
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'appGatewayBackendHttpSettings'
        properties: {
          port: backendPort
          protocol: 'Http'
          cookieBasedAffinity: cookieBasedAffinity
        }
      }
    ]
    httpListeners: [
      {
        name: 'appGatewayHttpListener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', applicationGatewayName, 'appGatewayFrontendIP')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', applicationGatewayName, 'appGatewayFrontendPort')
          }
          protocol: 'Http'
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'rule1'
        properties: {
          ruleType: 'Basic'
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', applicationGatewayName, 'appGatewayHttpListener')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', applicationGatewayName, 'appGatewayBackendPool')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', applicationGatewayName, 'appGatewayBackendHttpSettings')
          }
        }
      }
    ]
  }
}

// ASE with WebAPP
resource hostingEnvironment 'Microsoft.Web/hostingEnvironments@2021-03-01' = {
  name: aseName
  location: location
  kind: 'ASEV2'
  properties: {
    frontEndScaleFactor: 1
    internalLoadBalancingMode: internalLoadBalancingMode
    multiSize: 'Smalll'
    virtualNetwork: {
      id: resourceId('Microsoft.Network/VirtualNetworks/subnets', vnet_name, subnet_name[1])
      subnet: subnet_name[1]
    }
    zoneRedundant: false
  }
}

resource serverFarm 'Microsoft.Web/serverfarms@2021-03-01' = {
  name: appServicePlanName
  location: location
  properties: {
    hostingEnvironmentProfile: {
      id: hostingEnvironment.id
    }
  }
  sku: {
    name: 'I${workerPool}'
    tier: 'Isolated'
    size: 'I${workerPool}'
    family: 'I'
    capacity: numberOfWorkers
  }
}
resource website 'Microsoft.Web/sites@2021-03-01' = {
  name: websiteName
  location: location
  properties: {
    serverFarmId: serverFarm.id
    hostingEnvironmentProfile: {
      id: hostingEnvironment.id
    }
  }
}
