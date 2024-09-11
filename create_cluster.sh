#!/bin/bash

############
# Parameters
export K8S_VERSION="1.30"

account_id=555555555555
region=us-east-2
cluster_name=trieve-gpu
main_instance_type=t3.small
gpu_instance_type=g4dn.xlarge
gpu_count=1

eksctl create cluster -f - << EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: ${cluster_name}
  region: ${region}

nodeGroups:
  - name: main-basic
    instanceType: ${main_instance_type}
    desiredCapacity: 1
  - name: main-gpu
    labels: 
      eks-node: gpu
    instanceType: ${gpu_instance_type}
    desiredCapacity: ${gpu_count}
EOF

echo 'Deployment Done!'

aws eks update-kubeconfig --region ${region} --name ${cluster_name}

echo 'creating config map'
kubectl apply -f ./nvidia-device-plugin.yaml

echo 'Deploying helm chart'

helm repo add nvdp https://nvidia.github.io/k8s-device-plugin
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks nvdp

curl \
  -s \
  -o iam-policy.json \
  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.1/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name="${cluster_name}-load-balancer-controller-policy" \
  --policy-document file://iam-policy.json

eksctl utils associate-iam-oidc-provider --region=${region} --cluster=${cluster_name} --approve
eksctl create iamserviceaccount \
  --region="${region}" \
  --name="aws-load-balancer-controller" \
  --namespace="kube-system" \
  --cluster="${cluster_name}" \
  --role-name="${cluster_name}-aws-load-balancer-controller-role" \
  --attach-policy-arn="arn:aws:iam::${account_id}:policy/${cluster_name}-load-balancer-controller-policy" \
  --approve

helm upgrade --install \
  aws-load-balancer-controller \
  eks/aws-load-balancer-controller \
  --version="1.7.1" \
  --namespace="kube-system" \
  --set clusterName=${cluster_name} \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

helm upgrade -i nvdp nvdp/nvidia-device-plugin \
  --namespace kube-system \
  -f ../k8s/base/nvdp.yaml \
  --version 0.14.0 \
  --set config.name=nvidia-device-plugin \
  --force
