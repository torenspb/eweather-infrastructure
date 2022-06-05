output "application_address" {
  value       = "http://${aws_cloudfront_distribution.distribution.domain_name}/"
  description = "Application domain name"
}
