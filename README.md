# install-embeddings

Need
1) eksctl
2) aws cli
3) helm cli
4) kubectl


1) Create eks cluster and install plugins

Modify create_cluster.sh, the main thing that is important to edit
is your account id. 

Get your account id with `aws sts get-caller-identity`

https://github.com/devflowinc/install-embeddings/blob/d55047e2992a03ae0c98478a4a80d7dc8dcda6f7/create_cluster.sh#L7-L12

```sh
account_id=555555555555
region=us-east-2
cluster_name=trieve-gpu
main_instance_type=t3.small
gpu_instance_type=g4dn.xlarge
gpu_count=1
```

Ensure you have quotas for ${gpu_count}*4 under On-Demand G and VT instances in your region of choice

Run `./create_cluster.sh` to generate the cluster

2) Specify your embedding models

Modify embedding_models.yaml for the models that you want to use

3) Install the helm chart

```sh
helm upgrade -i embedding-release oci://registry-1.docker.io/trieve/embeddings-helm -f embedding_models.yaml
```

4) Get your model endpoints

```sh
kubectl get ing
```

![](./assets/ingress.png)


## Cleanup

```sh
helm uninstall embedding-release
./delete_cluster.sh
```

