output "subnet_public_ids" {
  value = module.service-network.subnet_public_ids
}

output "subnet_private_ids" {
  value = module.service-network.subnet_private_ids
}

output "internet_gateway_id" {
  value = module.service-network.internet_gateway_id
}
