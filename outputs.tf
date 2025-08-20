### outputs
output "vpc_id" {
  value = aws_vpc.main.id
}
output "dmz_subnet_id" {
  value = aws_subnet.dmz.id
}
output "internal_subnet_id" {
  value = aws_subnet.internal.id
}
output "jumpbox_public_ip" {
  value = aws_instance.jumpbox.public_ip
}
output "web_public_ip" {
  value = aws_instance.web.public_ip
}
output "internal_private_ip" {
  value = aws_instance.internal-box.private_ip
}
output "s3_website_endpoint" {
  description = "if bucket is created, this is the http endpoint"
  value       = aws_s3_bucket.website.website_endpoint
}