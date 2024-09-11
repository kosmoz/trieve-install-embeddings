cluster_name=trieve-gpu
region=us-east-2

helm uninstall nvdp -n kube-system
helm uninstall aws-load-balancer-controller -n kube-system
eksctl delete cluster --region=${region} --name=${cluster_name}
