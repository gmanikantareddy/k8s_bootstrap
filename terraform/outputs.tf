output "master_public_ip" {
  value = aws_instance.master[*].public_ip
}

output "worker_public_ips" {
  value = aws_instance.worker[*].public_ip
}


output "Argo_NodePort_value" {
  value = nonsensitive(data.aws_ssm_parameter.argo_port.value)
  
}

output "Argo_pass_value" {
  value = nonsensitive(data.aws_ssm_parameter.argo_pass.value)
  
}



output "worker_argo_urls" {
  value = [for ip in aws_instance.worker[*].public_ip : format("http://%s:%s", ip, nonsensitive(data.aws_ssm_parameter.argo_port.value))]
  description = "List of URLs in the form of http://<IP_ADDRESS>:<PORT>"
}