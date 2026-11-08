variable "subscription_id" {
  description = "The one subscription every environment shares (the work-mainsub situation)."
  type        = string
}

variable "location" {
  description = "Azure region for everything."
  type        = string
  default     = "uksouth"
}

variable "github_oidc_subject_prefix" {
  description = "Prefix of the OIDC sub claim GitHub issues for the repo: gh api repos/<owner>/<repo>/actions/oidc/customization/sub --jq .sub_claim_prefix (repos using immutable subjects include numeric owner/repo IDs)."
  type        = string
}

variable "owner_tag" {
  description = "Owner tag - required on every resource group by the subscription's Azure Policy."
  type        = string
  default     = "coatsc"
}
