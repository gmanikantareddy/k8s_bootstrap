#!/bin/bash


echo "${key_file_content}" | base64 --decode > /tmp/terraform-keypair.pem
chmod 600 /tmp/terraform-keypair.pem


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

# Install containerd
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


# Install Kubernetes packages
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl


echo whoami $(whoami)
# Join the Kubernetes cluster
JOIN_COMMAND=""
while true; do
  # Execute the command
  JOIN_COMMAND=$(ssh -o StrictHostKeyChecking=no -i /tmp/terraform-keypair.pem ubuntu@${MASTER_IP} "cat /tmp/join_command.sh")

  # Check the exit status of the command
  if [ $? -eq 0 ]; then
    echo "Command succeeded!"
    break
  else
    echo "Command failed, retrying in 5 seconds..."
    sleep 5
  fi
done
echo JOIN_COMMAND $JOIN_COMMAND
eval sudo $JOIN_COMMAND
