#!/bin/bash
sudo -u ubuntu -i 
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

# Initialize Kubernetes
IP_ADDRESS=$(hostname -I | awk '{print $1}')
echo $IP_ADDRESS
# --ignore-preflight-errors=all was used to bypass the CPU and Memory requirements check when using t2.small and below
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --control-plane-endpoint=$IP_ADDRESS --ignore-preflight-errors=all
echo "echoing whoami"
whoami
echo "echoing home"
export HOME=/root
echo $HOME
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Install Calico network plugin
#kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
#kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Get join command for worker nodes
kubeadm token create --print-join-command > /tmp/join_command.sh

kubectl create ns argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
sleep 20

kubectl get svc argocd-server -n argocd -o yaml >> argosvc.yaml
sed -i 's/type: ClusterIP/type: NodePort/' argosvc.yaml
kubectl apply -f argosvc.yaml
sleep 5

argonodeport=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[?(@.name == "http")].nodePort}')
parameter_name="/argoapp/server/config/nodeport"
command="aws ssm put-parameter --name "$parameter_name" --value "$argonodeport" --type "String" --overwrite --region=${region}"

sudo apt install python3.12-venv -y
mkdir python
python3 -m venv python
source python/bin/activate
pip3 install awscli --upgrade

eval $command

:'
target_count=${worker_count}
while true; do
  current_node_count=$(kubectl get nodes --no-headers | wc -l)
  adjusted_node_count=$((current_node_count - 1))
  if [ "$adjusted_node_count" -ge "$target_count" ]; then
     kubectl delete pods -l name=weave-net -n kube-system --grace-period=0 --force
     break
  else
     echo "sleeping for 30 seconds for all worker nodes to join"
     sleep 30
  fi
done
'

VERSION=$(curl -L -s https://raw.githubusercontent.com/argoproj/argo-cd/stable/VERSION)
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/download/v$VERSION/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64

echo $HOME
secret_name=""
while [ -z "$secret_name" ]; do
  echo "Waiting for the ArgoCD initial admin secret to be created..."
  sleep 10  # Wait for 10 seconds before checking again
  secret_name=$(kubectl -n argocd get secret | grep argocd-initial-admin-secret | awk '{print $1}')
done

admin_password=$(kubectl -n argocd get secret $secret_name -o jsonpath='{.data.password}' | base64 --decode)

NAMESPACE="argocd"
POD_NAME=$(kubectl get pods -n $NAMESPACE --no-headers -o custom-columns=":metadata.name" | grep "^argocd-server")
NODE_NAME=$(kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.spec.nodeName}')
NODE_IP=$(kubectl get node $NODE_NAME -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')

while true; do
  argocd login $NODE_IP:$argonodeport --insecure --username admin --password $admin_password
  if [ $? -eq 0 ]; then
    echo "ArgoCD login succeeded!"
    break
  else
    echo "ArgoCD login failed, retrying in 10 seconds..."
    sleep 10
  fi
done

source /python/bin/activate
aws ssm put-parameter --name "/argoapp/server/config/initialadminpass" --value $admin_password --type "String" --overwrite --region=${region}
#argocd app create guestbook --repo https://github.com/argoproj/argocd-example-apps.git --path guestbook --dest-namespace default --dest-server https://kubernetes.default.svc --directory-recurse --sync-policy auto

kubectl create ns jenkins
sudo mkdir -p /mnt/data
sudo chown -R 1000:1000 /mnt/data

#kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-ebs-csi-driver/release-1.10/deploy/kubernetes/overlays/stable/ecr/crd-ebsvolume.yaml

kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.31"
sleep 5
echo "${sc_file_content}" | base64 --decode > /root/aws_storageclass.yml
chmod 600 /root/aws_storageclass.yml

kubectl apply -f /root/aws_storageclass.yml
#kubectl delete pods -l name=weave-net -n kube-system --grace-period=0 --force


while true; do

  :'
  argocd app create jenkins \
    --repo https://charts.jenkins.io \
    --helm-chart jenkins \
    --revision 5.1.30 \
    --dest-namespace jenkins \
    --dest-server https://kubernetes.default.svc \
    --helm-set controller.admin.password=admin \
    --helm-set controller.serviceType=NodePort \
    --helm-set persistence.storageClass=ebs-sc \
    --sync-policy automated
'

  argocd app create jenkins \
    --repo https://github.com/gmanikantareddy/jenkins-helm-charts \
    --path charts/jenkins \
    --revision main \
    --dest-namespace jenkins \
    --dest-server https://kubernetes.default.svc \
    --values values.yaml \
    --parameter controller.admin.password=admin \
    --parameter controller.serviceType=NodePort \
    --parameter persistence.storageClass=ebs-sc \
    --sync-policy automated

  if [ $? -eq 0 ]; then
    echo "Jenkins app creation through ArgoCD succeeded!"
    break
  else
    echo "Jenkins app creation through ArgoCD failed, retrying in 10 seconds..."
    sleep 10
  fi
done




touch /tmp/assmp_updated