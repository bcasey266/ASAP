output "spn_api" {
  description = "Manual step required on the first deploy of the platform"
  value       = var.enable_apim == true ? "Azure AD App Registration API Permissions: ${module.APIM[0].api_admin_consent}" : "N/A"
}

output "email_auth" {
  description = "Manual step required on the first deploy of the platform"
  value       = var.enable_notifications == true ? "Email Authorization: ${module.Notifications[0].authorize}" : "N/A"
}
