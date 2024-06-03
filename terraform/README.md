
# AWS Kubernetes Cluster Setup

This script automates the setup of a Kubernetes cluster on AWS using EC2 instances with Ubuntu 20.04 LTS. It creates one master node and multiple worker nodes, configuring them with containerd as the container runtime and Calico as the network plugin.

## Prerequisites

Before running the script, make sure you have:

-   An AWS account with appropriate permissions to create EC2 instances.
-   AWS CLI installed and configured with your AWS credentials.
-   An SSH key pair created in the AWS region where you intend to launch the instances.
-   Terraform installed

## Usage

1.  Clone the repository to your local machine:
      
    `git clone https://github.com/gmanikantareddy/k8s_bootstrap.git
    
2.  Navigate to the cloned directory:
        
    `cd aws-kubernetes-cluster-setup/terraform` 
    
3.  Update the `terraform.tfvars` file with your desired configuration. You need to specify the AWS region, AMI ID, instance types, key name, security group name, and the number of master and worker nodes.
    
4.  Ensure your SSH private key file (`terraform-keypair.pem`) is in the same directory as the script.
    
5.  Run the Terraform script:
    
   terraform init
   terraform plan
   terraform apply 
    
6.  Wait for the script to complete. Once finished, you'll have a fully functional Kubernetes cluster ready for use.
    

## Configuration

The `terraform.tfvars` file contains the configuration parameters for the script. You can adjust these values according to your requirements:

-   `region`: AWS region where the EC2 instances will be launched.
-   `ami_id`: ID of the Ubuntu 20.04 LTS AMI in the specified region.
-   `instance_type`: EC2 instance type (e.g., t2.micro).
-   `key_name`: Name of the SSH key pair used for accessing the instances.
-   `security_group_name`: Name of the security group for the EC2 instances.
-   `master_instance_count`: Number of master nodes in the Kubernetes cluster.
-   `worker_instance_count`: Number of worker nodes in the Kubernetes cluster.