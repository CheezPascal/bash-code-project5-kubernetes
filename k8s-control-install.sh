#!/bin/bash

# Function to install common dependencies
install_common_dependencies() {
    sudo apt update
    sudo apt install docker.io -y
    sudo systemctl enable docker
    sudo systemctl start docker

    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

    sudo apt update
    sudo apt install kubeadm kubelet kubectl -y
    sudo apt-mark hold kubeadm kubelet kubectl

    sudo swapoff -a
    sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

    # Configure kernel modules
    echo "overlay" | sudo tee /etc/modules-load.d/containerd.conf
    echo "br_netfilter" | sudo tee -a /etc/modules-load.d/containerd.conf

    sudo modprobe overlay
    sudo modprobe br_netfilter

    # Configure sysctl
    echo "net.bridge.bridge-nf-call-ip6tables = 1" | sudo tee /etc/sysctl.d/kubernetes.conf
    echo "net.bridge.bridge-nf-call-iptables = 1" | sudo tee -a /etc/sysctl.d/kubernetes.conf
    echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.d/kubernetes.conf
    sudo sysctl --system
}

# Function for control-plane setup
setup_control_plane() {
    sudo hostnamectl set-hostname master-node

    # Add cluster IPs to /etc/hosts
    echo "# These are the K8s hosts" | sudo tee -a /etc/hosts
    echo "192.168.30.159 " | sudo tee -a /etc/hosts
    echo "192.168.30.160 " | sudo tee -a /etc/hosts
    echo "192.168.30.161 " | sudo tee -a /etc/hosts
    echo "192.168.30.162 " | sudo tee -a /etc/hosts

    echo 'KUBELET_EXTRA_ARGS="--cgroup-driver=cgroupfs"' | sudo tee /etc/default/kubelet
    sudo systemctl daemon-reload && sudo systemctl restart kubelet

    # Configure Docker cgroup driver
    cat <<EOF | sudo tee /etc/docker/daemon.json
{
    "exec-opts": ["native.cgroupdriver=systemd"],
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m"
    },
    "storage-driver": "overlay2"
}
EOF

    sudo systemctl daemon-reload && sudo systemctl restart docker

    # Configure kubelet
    sudo mkdir -p /etc/systemd/system/kubelet.service.d
    echo 'Environment="KUBELET_EXTRA_ARGS=--fail-swap-on=false"' | sudo tee /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
    sudo systemctl daemon-reload && sudo systemctl restart kubelet

    # Initialize Kubernetes cluster
    sudo kubeadm init --control-plane-endpoint=master-node --upload-certs | tee k8s-initfile.txt

    # Configure kubectl for the current user
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config

    # Deploy a pod network
    kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
    kubectl taint nodes --all node-role.kubernetes.io/control-plane-
}

# Function for worker node setup
setup_worker_node() {
    # Stop AppArmor
    sudo systemctl stop apparmor
    sudo systemctl disable apparmor
    sudo systemctl restart containerd.service

    # Join the Kubernetes cluster
    read -p "Enter the Kubernetes join command (as provided by the control plane): " join_command
    eval "sudo $join_command"
}

# Function to uninstall Kubernetes
uninstall_kubernetes() {
    echo "Uninstalling Kubernetes..."
    sudo kubeadm reset -f
    sudo apt purge kubeadm kubelet kubectl docker.io -y
    sudo apt autoremove -y
    sudo rm -rf /etc/kubernetes /var/lib/etcd /var/lib/kubelet /var/lib/dockershim /etc/cni /opt/cni
    sudo rm -rf ~/.kube
    echo "Kubernetes has been uninstalled."
}

# Main script logic
clear
echo "Choose an option:"
echo "1. Install Control Plane Node"
echo "2. Install Worker Node"
echo "3. Uninstall Kubernetes"
read -p "Enter your choice (1, 2, or 3): " option

if [[ "$option" == "1" ]]; then
    install_common_dependencies
    setup_control_plane
elif [[ "$option" == "2" ]]; then
    install_common_dependencies
    setup_worker_node
elif [[ "$option" == "3" ]]; then
    uninstall_kubernetes
else
    echo "Invalid choice. Exiting."
    exit 1
fi

# Script complete
echo "Operation complete."
