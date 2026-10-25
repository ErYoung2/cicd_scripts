#!/bin/bash

# 确保脚本以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "[-] 请使用 root 权限运行此脚本 (例如: sudo bash setup-k3s-debian.sh)"
  exit 1
fi

echo "[+] 开始配置 Debian 系统以准备安装 K3s..."

# 1. 更新系统并使用 apt 安装基础工具
echo "[+] 更新软件源并安装基础工具..."
apt update -y && apt upgrade -y
apt install -y curl apt-transport-https ca-certificates ufw

# 2. 关闭 Swap (Kubernetes 强烈要求)
echo "[+] 正在关闭 Swap 交换分区..."
swapoff -a
sed -i '/swap/s/^/#/' /etc/fstab

# 3. 配置内核参数 (确保转发和桥接流量正常)
echo "[+] 配置内核网络转发..."
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

# 4. 一键安装 K3s (使用国内加速源)
echo "[+] 正在安装 K3s..."
curl -sfL https://get.k3s.io | sh -

# 5. 循环等待 k3s.yaml 配置文件生成（最多等待 30 秒）
echo "[+] 等待 K3s 服务启动并生成配置文件..."
counter=0
while [ ! -f /etc/rancher/k3s/k3s.yaml ]; do
  sleep 2
  counter=$((counter + 1))
  if [ $counter -ge 15 ]; then
    echo "[-] 错误：K3s 启动超时，未找到 /etc/rancher/k3s/k3s.yaml"
    echo "[-] 请使用 'sudo systemctl status k3s' 或 'journalctl -u k3s' 检查错误原因。"
    exit 1
  fi
done

# 6. 配置当前用户的 kubectl 权限
TARGET_USER="${SUDO_USER:-root}"
TARGET_HOME=$(eval echo ~$TARGET_USER)

echo "[+] 配置 kubectl 权限给用户: $TARGET_USER..."
mkdir -p "$TARGET_HOME/.kube"
cp /etc/rancher/k3s/k3s.yaml "$TARGET_HOME/.kube/config"
chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.kube"
chmod 600 "$TARGET_HOME/.kube/config"

# 7. 验证安装结果
echo "[+] 验证 K3s 集群状态..."
export KUBECONFIG="$TARGET_HOME/.kube/config"
kubectl get node

echo "=========================================="
echo "[✔] Debian K3s 自动化部署完成！"
echo "[i] 你现在可以执行 'kubectl get nodes' 来查看集群状态。"
echo "=========================================="