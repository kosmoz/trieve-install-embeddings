#!/bin/bash

usage() {
  echo "

usage: 

export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query "Account" --output text)"
export AWS_REGION=us-east-2
export CLUSTER_NAME=trieve-gpu
export CPU_INSTANCE_TYPE=t3.small
export GPU_INSTANCE_TYPE=g4dn.xlarge
export GPU_COUNT=1

$0 
  "
}

############
# Parameters
export K8S_VERSION="1.30"

[ -z $AWS_REGION ] && echo "error: AWS_REGION is not set" && usage && exit
[ -z $CLUSTER_NAME ] && echo "CLUSTER_NAME is not set" && usage && exit
[ -z $AWS_ACCOUNT_ID ] && echo "AWS_ACCOUNT_ID is not set" && usage && exit
[ -z $GPU_COUNT ] && echo "GPU_COUNT is not set" && usage && exit
[ -z $GPU_INSTANCE_TYPE ] && echo "GPU_INSTANCE_TYPE is not set" && usage && exit
[ -z $CPU_INSTANCE_TYPE ] && echo "CPU_INSTANCE_TYPE is not set" && usage && exit

echo "Provision a cluster in $(tput bold)${AWS_REGION}$(tput sgr0) named ${CLUSTER_NAME} for account ${AWS_ACCOUNT_ID}"
echo "Cluster breakdown:"
echo ""
echo "+ ${GPU_COUNT} * $(tput bold)${GPU_INSTANCE_TYPE}$(tput sgr0)"
echo "+ 1 * $(tput bold)${CPU_INSTANCE_TYPE}$(tput sgr0)"

read -p "Confirm? [y/N]? " -r
if [[ $REPLY =~ ^[Yy]$ ]]
then
eksctl create cluster -f - << EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: ${CLUSTER_NAME}
  region: ${AWS_REGION}

nodeGroups:
  - name: main-basic
    instanceType: ${CPU_INSTANCE_TYPE}
    desiredCapacity: 1
  - name: main-gpu
    labels: 
      eks-node: gpu
    instanceType: ${GPU_INSTANCE_TYPE}
    desiredCapacity: ${GPU_COUNT}
EOF

echo 'Deployment Done!'

aws eks update-kubeconfig --region ${AWS_REGION} --name ${CLUSTER_NAME}

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
  --policy-name="${CLUSTER_NAME}-load-balancer-controller-policy" \
  --policy-document file://iam-policy.json

eksctl utils associate-iam-oidc-provider --region=${AWS_REGION} --cluster=${CLUSTER_NAME} --approve
eksctl create iamserviceaccount \
  --region="${AWS_REGION}" \
  --name="aws-load-balancer-controller" \
  --namespace="kube-system" \
  --cluster="${CLUSTER_NAME}" \
  --role-name="${CLUSTER_NAME}-aws-load-balancer-controller-role" \
  --attach-policy-arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${CLUSTER_NAME}-load-balancer-controller-policy" \
  --approve

helm upgrade --install \
  aws-load-balancer-controller \
  eks/aws-load-balancer-controller \
  --version="1.7.1" \
  --namespace="kube-system" \
  --set clusterName=${CLUSTER_NAME} \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

helm upgrade -i nvdp nvdp/nvidia-device-plugin \
  --namespace kube-system \
  -f nvdp.yaml \
  --version 0.14.0 \
  --set config.name=nvidia-device-plugin \
  --force
else
echo "Apply canceled"
fi

