#!/bin/bash

set -e

usage() {
  echo "

usage: 

export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query "Account" --output text)"
export AWS_REGION=us-east-2
export CLUSTER_NAME=trieve-gpu
export CPU_INSTANCE_TYPE=t3.medium
export GPU_INSTANCE_TYPE=g4dn.xlarge
export GPU_COUNT=1
export REPO_USERNAME=test
export REPO_PASSWORD=test
export DOMAIN=trieve.tld.com

$0 
  "
}

############
# Parameters
export K8S_VERSION="1.30"
export CPU_INSTANCE_COUNT=5

[ -z $AWS_REGION ] && echo "error: AWS_REGION is not set" && usage && exit
[ -z $CLUSTER_NAME ] && echo "CLUSTER_NAME is not set" && usage && exit
[ -z $AWS_ACCOUNT_ID ] && echo "AWS_ACCOUNT_ID is not set" && usage && exit
[ -z $GPU_COUNT ] && echo "GPU_COUNT is not set" && usage && exit
[ -z $GPU_INSTANCE_TYPE ] && echo "GPU_INSTANCE_TYPE is not set" && usage && exit
[ -z $CPU_INSTANCE_TYPE ] && echo "CPU_INSTANCE_TYPE is not set" && usage && exit
[ -z $REPO_USERNAME ] && echo "REPO_USERNAME is not set" && usage && exit
[ -z $REPO_PASSWORD ] && echo "REPO_PASSWORD is not set" && usage && exit
[ -z $DOMAIN ] && echo "DOMAIN is not set" && usage && exit

echo "Provision a cluster in $(tput bold)$AWS_REGION$(tput sgr0) named $CLUSTER_NAME for account $AWS_ACCOUNT_ID"
echo "Cluster breakdown:"
echo ""
echo "+ $GPU_COUNT * $(tput bold)$GPU_INSTANCE_TYPE$(tput sgr0)"
echo "+ $CPU_INSTANCE_COUNT * $(tput bold)$CPU_INSTANCE_TYPE$(tput sgr0)"

read -p "Confirm? [y/N]? " -r
if [[ $REPLY =~ ^[Yy]$ ]]
then
eksctl create cluster -f - << EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: $CLUSTER_NAME
  region: $AWS_REGION
  version: "$K8S_VERSION"

iam:
  podIdentityAssociations:
    - namespace: kube-system
      serviceAccountName: aws-load-balancer-controller
      createServiceAccount: true
      wellKnownPolicies:
        awsLoadBalancerController: true


managedNodeGroups:
  - name: main
    instanceType: $CPU_INSTANCE_TYPE
    desiredCapacity: $CPU_INSTANCE_COUNT
    maxSize: 8
    minSize: 4
    volumeSize: 20
    ssh:
      allow: false
    iam:
      withAddonPolicies:
        awsLoadBalancerController: true
        ebs: true
  - name: gpu
    labels:
      eks-node: gpu
    instanceType: $GPU_INSTANCE_TYPE
    desiredCapacity: $GPU_COUNT

vpc:
  cidr: 10.0.0.0/16

addonsConfig:
  autoApplyPodIdentityAssociations: true
  disableDefaultAddons: false


addons:
  - name: eks-pod-identity-agent
    version: latest
  - name: vpc-cni
    version: latest
    useDefaultPodIdentityAssociations: true
  - name: coredns
    version: latest
  - name: kube-proxy
    version: latest
  - name: aws-ebs-csi-driver
    version: latest
    useDefaultPodIdentityAssociations: true
EOF

echo 'Deployment Done!'

aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME

kubectl patch sc gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

echo 'creating config map'
kubectl apply -f ./nvidia-device-plugin.yaml

echo 'Deploying helm chart'

helm upgrade --install --repo https://nvidia.github.io/k8s-device-plugin nvdp nvidia-device-plugin \
  --namespace kube-system \
  -f nvdp.yaml \
  --version 0.14.0 \
  --set config.name=nvidia-device-plugin \
  --force

helm upgrade --install --repo https://aws.github.io/eks-charts aws-load-balancer-controller aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set ingressClassConfig.default=true


glasskube bootstrap --yes
glasskube repo add trieve https://trieve.private.dl.glasskube.dev/packages/ --username $REPO_USERNAME --password $REPO_PASSWORD
glasskube install trieve-aws --use-default=all --value "domain=$DOMAIN" --yes


else
echo "Apply canceled"
fi
