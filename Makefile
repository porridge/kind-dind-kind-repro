KIND_VERSION ?= 0.8.1
KINDEST_NODE_IMAGE ?= mesoporridge/kindest-node:0.1.0
DIND_IMAGE ?= mesoporridge/dind:0.1.0

KIND_PATH = $(CURDIR)/bin/kind-$(KIND_VERSION)

.PHONY: apply-pod
apply-pod:
	sed 's,%KINDEST_NODE_IMAGE%,$(KINDEST_NODE_IMAGE),g;s,%DIND_IMAGE%,$(DIND_IMAGE),g' dind-pod.yaml.in | kubectl apply -f -

.PHONY: follow-logs
follow-logs:
	kubectl logs -f dind-pod --pod-running-timeout=60s

.PHONY: push-images
push-images:
	docker build -t $(DIND_IMAGE) -f Dockerfile.dind-image --build-arg KIND_VERSION=$(KIND_VERSION) $(CURDIR)
	docker build -t $(KINDEST_NODE_IMAGE) -f Dockerfile.kindest-node-image $(CURDIR)
	docker push $(DIND_IMAGE)
	docker push $(KINDEST_NODE_IMAGE)

.PHONY: clean
clean: $(KUBECONFIG_PATH)
	sed 's,%KINDEST_NODE_IMAGE%,$(KINDEST_NODE_IMAGE),g;s,%DIND_IMAGE%,$(DIND_IMAGE),g' dind-pod.yaml.in | kubectl delete -f -

$(CURDIR)/bin/kind-%:
	curl -L -o $@ https://github.com/kubernetes-sigs/kind/releases/download/v$*/kind-linux-amd64
	chmod +x $@

