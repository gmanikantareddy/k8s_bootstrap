import boto3
import time
import paramiko
import json
import time
from botocore.exceptions import NoCredentialsError, PartialCredentialsError

# Read configuration from JSON file
with open('config.json') as config_file:
    config = json.load(config_file)

REGION = config['region']
AMI_ID = config['ami_id']
INSTANCE_TYPE = config['instance_type']
KEY_NAME = config['key_name']
SECURITY_GROUP_NAME = config['security_group_name']
MASTER_INSTANCE_COUNT = config['master_instance_count']
WORKER_INSTANCE_COUNT = config['worker_instance_count']

# Scripts
PREREQUISITES = """
# Disable swap
sudo swapoff -a


# Install necessary packages
sudo apt-get update -y
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common

# Load necessary kernel modules
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Set sysctl parameters required by Kubernetes
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

# Apply sysctl parameters without reboot
sudo sysctl --system
"""

INSTALL_CONTAINERD = """
sudo apt-get update -y
sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
sudo tee /etc/containerd/config.toml > /dev/null << EOF
[plugins."io.containerd.grpc.v1.cri".containerd]
  sandbox_image = "registry.k8s.io/pause:3.9"
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
    SystemdCgroup = true
EOF
sudo systemctl restart containerd
sudo systemctl enable containerd
"""

INSTALL_KUBERNETES = """
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
"""

RENAME_INSTANCE_TAG = """
instance_id=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
aws ec2 create-tags --resources $instance_id --tags Key=Name,Value=k8s-master
"""

KUBEADM_INIT = """
IP_ADDRESS=$(hostname -I | awk '{print $1}')
echo $IP_ADDRESS
sudo kubeadm init --pod-network-cidr=192.168.0.0/16 --control-plane-endpoint=$IP_ADDRESS --ignore-preflight-errors=all
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
"""

INSTALL_CALICO = """
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
"""

JOIN_NODE_COMMAND = """
kubeadm token create --print-join-command
"""

# Create EC2 resource
ec2 = boto3.resource('ec2', region_name=REGION)
client = boto3.client('ec2', region_name=REGION)

def create_security_group():
    try:
        response = client.describe_security_groups(GroupNames=[SECURITY_GROUP_NAME])
        security_group_id = response['SecurityGroups'][0]['GroupId']
    except client.exceptions.ClientError:
        response = client.create_security_group(
            GroupName=SECURITY_GROUP_NAME,
            Description='Kubernetes security group',
            VpcId=client.describe_vpcs()['Vpcs'][0]['VpcId']
        )
        security_group_id = response['GroupId']
        client.authorize_security_group_ingress(
            GroupId=security_group_id,
            IpPermissions=[
                {'IpProtocol': 'tcp', 'FromPort': 22, 'ToPort': 22, 'IpRanges': [{'CidrIp': '0.0.0.0/0'}]},
                {'IpProtocol': 'tcp', 'FromPort': 80, 'ToPort': 80, 'IpRanges': [{'CidrIp': '0.0.0.0/0'}]},
                {'IpProtocol': 'tcp', 'FromPort': 443, 'ToPort': 443, 'IpRanges': [{'CidrIp': '0.0.0.0/0'}]},
                {'IpProtocol': 'tcp', 'FromPort': 6443, 'ToPort': 6443, 'IpRanges': [{'CidrIp': '0.0.0.0/0'}]},
                {'IpProtocol': 'tcp', 'FromPort': 2379, 'ToPort': 2380, 'IpRanges': [{'CidrIp': '0.0.0.0/0'}]},
                {'IpProtocol': 'tcp', 'FromPort': 10250, 'ToPort': 10255, 'IpRanges': [{'CidrIp': '0.0.0.0/0'}]},
                {'IpProtocol': 'tcp', 'FromPort': 30000, 'ToPort': 32767, 'IpRanges': [{'CidrIp': '0.0.0.0/0'}]}
            ]
        )
    return security_group_id

def launch_instances(count, security_group_id):
    instances = ec2.create_instances(
        ImageId=AMI_ID,
        InstanceType=INSTANCE_TYPE,
        KeyName=KEY_NAME,
        MinCount=count,
        MaxCount=count,
        SecurityGroupIds=[security_group_id],
        TagSpecifications=[{
            'ResourceType': 'instance',
            'Tags': [{'Key': 'Name', 'Value': 'k8s-node'}]
        }]
    )
    for instance in instances:
        instance.wait_until_running()
        instance.reload()
    return instances

def execute_commands(instance, commands):
    key = paramiko.RSAKey.from_private_key_file(f"{KEY_NAME}.pem")
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(instance.public_ip_address, username='ubuntu', pkey=key)
    for command in commands:
        stdin, stdout, stderr = client.exec_command(command)
        print(stdout.read().decode())
        print(stderr.read().decode())
    client.close()

def main():
    try:
        security_group_id = create_security_group()
        total_instances = MASTER_INSTANCE_COUNT + WORKER_INSTANCE_COUNT
        instances = launch_instances(total_instances, security_group_id)
        master_instance = instances[0]
        worker_instances = instances[1:]

        commands_master = [PREREQUISITES, INSTALL_CONTAINERD, INSTALL_KUBERNETES, KUBEADM_INIT, INSTALL_CALICO, RENAME_INSTANCE_TAG]
        time.sleep(120)
        execute_commands(master_instance, commands_master)

        # Get join command
        key = paramiko.RSAKey.from_private_key_file(f"{KEY_NAME}.pem")
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(master_instance.public_ip_address, username='ubuntu', pkey=key)
        stdin, stdout, stderr = client.exec_command(JOIN_NODE_COMMAND)
        join_command = stdout.read().decode().strip()
        join_command = "sudo " + join_command
        client.close()

        commands_worker = [PREREQUISITES, INSTALL_CONTAINERD, INSTALL_KUBERNETES, join_command]
        for worker_instance in worker_instances:
            execute_commands(worker_instance, commands_worker)

        print("Kubernetes cluster setup is complete.")

    except (NoCredentialsError, PartialCredentialsError):
        print("AWS credentials not configured properly.")

if __name__ == "__main__":
    main()
