# KIND cluster in docker-in-docker container in a k8s (KIND) cluster

This repo is a minimum repro case for the issue with running `kind` in a docker-in-docker container
that is in turn a part of a kubernetes pod.

## The issue

The issue is that kubelet gets confused about some unexpected cgroups and SIGKILLs everything including itself.

I [reported this on slack](https://kubernetes.slack.com/archives/CEKK1KTN2/p1587988851297500?thread_ts=1575376979.206200&cid=CEKK1KTN2)
earlier but only managed to come up with a fairly simple repro case now.

This was also described in [a blog post by Jie](https://d2iq.com/blog/running-kind-inside-a-kubernetes-cluster-for-continuous-integration) - look for

> However, when we try to run this in CI (in the production Kubernetes cluster), things start to fail.

That post describes a [workaround](https://github.com/jieyu/docker-images/tree/master/kind-cluster) that
injects [some additional code](https://github.com/jieyu/docker-images/blob/master/kind-cluster/node/entrypoint-wrapper.sh)
*around* the `kind` entrypoint to further massage the cgroup filesystem and requires
[patching the kubelet config](https://github.com/jieyu/docker-images/blob/master/kind-cluster/kind-config.yaml).

Because of the maintenance burden of these rather invasive changes I'm looking for a better alternative.

## Prerequisites

* `kubectl`
* `make`
* a k8s cluster

Note: You need a "real" k8s cluster, where the host has the actual root of `/sys/fs/cgroup/systemd` filesystem mounted.
This is because the `dind` docker image does not work without it.

## Instructions

The default `make` target `apply-pod` will apply a pod in the default context, which reproduces the issue.

After running it, wait for `dind-pod` to start running, and then see its logs:

```bash
$ make
sed 's,%KINDEST_NODE_IMAGE%,mesoporridge/kindest-node:0.1.0,g;s,%DIND_IMAGE%,mesoporridge/dind:0.1.0,g' dind-pod.yaml.in | kubectl apply -f -
pod/dind-pod created
$ kubectl get pod -w dind-pod
NAME                           READY   STATUS              RESTARTS   AGE
dind-pod                       0/1     ContainerCreating   0          1s
dind-pod                       1/1     Running             0          2s
CTRL+C
$ make follow-logs
kubectl logs -f dind-pod --pod-running-timeout=60s
+ set -o errexit
[...]
 ✗ Starting control-plane 🕹️
ERROR: failed to create cluster: failed to init node with kubeadm: command "docker exec --privileged kind-control-plane kubeadm init --ignore-preflight-errors=all --config=/kind/kubeadm.conf --skip-token-print --v=6" failed with error: exit status 137
[...]
```

Note: I think I've seen at least once that the cluster comes up OK. I think it might be a race condition
between kubelet declaring that it's healthy and going on its killing spree. Just run `make clean` (which removes the pod)
and retry if that is the case.

The output is rather verbose, so here is a summary:
1. It starts with the output from the entrypoint of the `dind` image: starting `dockerd` with an appropriate `--cgroup-parent`
   and waiting for it to come up.
1. Then (`POD COMMAND STARTING`) the actual pod command starts, which invokes `kind create cluster`
1. Debug output from `kind` follows, including `kubeadm` output.
1. After that (`KIND CLUSTER CREATION FAILED`) we dump the log from the control plane container.
1. This includes the `kind` entrypoint log from `set -x`, including some more detailed debug output
   in the `fix_cgroup` function.
1. Finally, the systemd output from the control plane "node"

## Hacking this repro case

Additional pre-requisites:
* `docker`
* `curl`

The docker images used are defined as variables in the `Makefile`.
See the `push-images` target for how they are built. All sources are in this repo.
Just run:
 
```bash
make push-images apply-pod KINDEST_NODE_IMAGE=your/tag DIND_IMAGE=your/other-tag
```

if you want to rebuild them yourself.

### `kindest-node`

The only modification from the original is a few debugging instructions added to the `fix_cgroup` function,
and a `set -x` at the top.

### `dind`

A simple docker-in-docker image with the `kind` binary included.
