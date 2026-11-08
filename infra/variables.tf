variable "environment" {
  description = "Environment label - also the Environment tag value: Development, UAT or Production."
  type        = string

  validation {
    condition     = contains(["Development", "UAT", "Production"], var.environment)
    error_message = "environment must be exactly Development, UAT or Production - tag values are case-sensitive."
  }
}

variable "environment_key" {
  description = "Short name used in resource names: dev, uat or prod."
  type        = string
}

variable "resource_group_name" {
  description = "The environment's resource group, created by bootstrap/. The pipeline's identity has rights on this group only."
  type        = string
}

variable "owner_tag" {
  description = "Owner tag."
  type        = string
  default     = "coatsc"
}
