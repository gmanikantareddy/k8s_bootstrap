variable "region" {
  description = "AWS region"
  type        = string
}

variable "ami_id" {
  description = "AMI ID for Ubuntu 20.04 LTS"
  type        = string
}

variable "instance_type_master" {
  description = "EC2 instance type"
  type        = string
}


variable "instance_type_worker" {
  description = "EC2 instance type"
  type        = string
}

variable "key_name" {
  description = "Name of the SSH key pair"
  type        = string
}

variable "private_key_path" {
  description = "Path to the private key file"
  type        = string
}



variable "security_group_name" {
  description = "Name of the security group"
  type        = string
  }

variable "master_instance_count" {
  description = "Number of master instances"
  type        = number
  default     = 1
}

variable "worker_instance_count" {
  description = "Number of worker instances"
  type        = number
  default     = 3
}
