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

   ingress {
    from_port   = 179
    to_port     = 179
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

    ingress {
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
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
  iam_instance_profile = aws_iam_instance_profile.ec2_k8smaster_instance_profile.name

  tags = {
    Name = "k8s-master"
  }

  user_data = templatefile("scripts/master_setup.sh", {
    region = var.region
    worker_count = var.worker_instance_count
    sc_file_content = base64encode(file("aws_storageclass.yaml"))
  })
}


resource "aws_instance" "worker" {
  depends_on = [aws_instance.master]
  count         = var.worker_instance_count
  ami           = var.ami_id
  instance_type = var.instance_type_worker
  key_name      = var.key_name
  security_groups = [aws_security_group.k8s_sg.name]
  iam_instance_profile = aws_iam_instance_profile.ec2_k8sworker_instance_profile.name

  tags = {
    Name = "k8s-worker"
  }

  user_data = templatefile("scripts/worker_setup.sh", {
    MASTER_IP = aws_instance.master.0.public_ip
    key_file_content = base64encode(file("terraform-keypair.pem"))
  })

}

resource "null_resource" "wait_for_master_setup" {
  count = var.master_instance_count

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("terraform-keypair.pem")
    host        = element(aws_instance.master.*.public_ip, count.index)
  }

  provisioner "remote-exec" {
    inline = [
      "while [ ! -f /tmp/assmp_updated ]; do echo 'Waiting for setup to complete...'; sleep 10; done"
    ]
  }

  depends_on = [aws_instance.master]
}


data "aws_ssm_parameter" "argo_port" {

  depends_on = [null_resource.wait_for_master_setup]
  name = "/argoapp/server/config/nodeport"

  
}

data "aws_ssm_parameter" "argo_pass" {

  depends_on = [null_resource.wait_for_master_setup]
  name = "/argoapp/server/config/initialadminpass"

  
}



