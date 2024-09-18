# install-embeddings

Need

- [eksctl](https://eksctl.io/installation/) _(min. version 0.190.0)_
- [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [helm cli](https://helm.sh/docs/intro/install/#helm)
- [kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl)
- [glasskube](https://glasskube.dev/docs/getting-started/install/)

### Check AWS quota

Ensure you have quotas for

- ${gpu_count}*4 for On-Demand G and VT instances in the region of choice
- At least 1 load-balancer per each model you want. (Not per server running)

### Create eks cluster and install needed plugins

Modify the following lines in `create_cluster.sh`

To get your account id run

```sh
aws sts get-caller-identity
```

https://github.com/devflowinc/install-embeddings/blob/d55047e2992a03ae0c98478a4a80d7dc8dcda6f7/create_cluster.sh#L7-L12

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

