provider "aws" {
  region = var.region
}

resource "aws_security_group" "k8s_sg" {
  name        = var.security_group_name
  description = "Kubernetes security group"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 10250
    to_port     = 10255
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "master" {
  count         = var.master_instance_count
  ami           = var.ami_id
  instance_type = var.instance_type_master
  key_name      = var.key_name
  security_groups = [aws_security_group.k8s_sg.name]

  tags = {
    Name = "k8s-master"
  }

    provisioner "file" {
      source      = "scripts/master_setup.sh"
      destination = "/tmp/master_setup.sh"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(var.private_key_path)
      host        = self.public_ip
    }
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/master_setup.sh",
      "sudo /tmp/master_setup.sh"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(var.private_key_path)
      host        = self.public_ip
    }


  }


}


resource "aws_instance" "worker" {
  count         = var.worker_instance_count
  ami           = var.ami_id
  instance_type = var.instance_type_worker
  key_name      = var.key_name
  security_groups = [aws_security_group.k8s_sg.name]

  tags = {
    Name = "k8s-worker"
  }

    provisioner "file" {
      source      = "scripts/worker_setup.sh"
      destination = "/tmp/worker_setup.sh"
    
     connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(var.private_key_path)
      host        = self.public_ip
    }
  }

      provisioner "file" {
      source      = "terraform-keypair.pem"
      destination = "/tmp/terraform-keypair.pem"
    
     connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(var.private_key_path)
      host        = self.public_ip
    }
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 600 /tmp/terraform-keypair.pem",
      "chmod +x /tmp/worker_setup.sh",
      "sudo /tmp/worker_setup.sh ${aws_instance.master.0.public_ip}"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(var.private_key_path)
      host        = self.public_ip
    }


  }


}

