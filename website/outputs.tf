output "website_public_ip" {
  value = aws_instance.web.public_ip
}

output "website_url" {
  value = "http://${aws_instance.web.public_ip}"
}

output "alb_url" {
  value = "http://${aws_lb.website.dns_name}"
}
