SHELL := /bin/bash
.DEFAULT_GOAL := help

DATE     := $(shell date +%Y%m%d)
DIST_DIR := dist
IMG_DIR  := $(DIST_DIR)/images

# ---------------------------------------------------------------------------
# Services
# ---------------------------------------------------------------------------
# Java services share build context = services/
JAVA_SERVICES    := api-user api-order api-product api-auth bff
# These use build context = . (project root)
ROOT_CTX_SERVICES := frontend ssl-proxy
ALL_SERVICES      := $(JAVA_SERVICES) $(ROOT_CTX_SERVICES)

POSTGRES_IMAGE := docker.io/library/postgres:16-alpine

# ---------------------------------------------------------------------------
# Phony targets
# ---------------------------------------------------------------------------
.PHONY: help build clean bundle images dist \
        $(addprefix build-,$(ALL_SERVICES)) \
        $(addprefix image-,$(ALL_SERVICES)) \
        image-postgres

# ---------------------------------------------------------------------------
# help
# ---------------------------------------------------------------------------
help:
	@echo "Usage:"
	@echo "  make build          Build all container images"
	@echo "  make build-<svc>    Build one image (e.g. make build-api-user)"
	@echo "  make images         Build + export all images to $(IMG_DIR)/"
	@echo "  make image-<svc>    Build + export one image"
	@echo "  make image-postgres Pull + export postgres image"
	@echo "  make bundle         Package deploy bundle to $(DIST_DIR)/"
	@echo "  make dist           Build bundle + images"
	@echo "  make clean          Remove $(DIST_DIR)/"
	@echo ""
	@echo "Parallel build:  make -j4 build"
	@echo ""
	@echo "Services: $(ALL_SERVICES)"

# ---------------------------------------------------------------------------
# Build targets
# ---------------------------------------------------------------------------
# Java services: context = services/
$(addprefix build-,$(JAVA_SERVICES)):
	podman build -t localhost/$(@:build-%=%):latest \
		-f services/$(@:build-%=%)/Dockerfile \
		services/

# Root-context services: context = .
$(addprefix build-,$(ROOT_CTX_SERVICES)):
	podman build -t localhost/$(@:build-%=%):latest \
		-f services/$(@:build-%=%)/Dockerfile \
		.

build: $(addprefix build-,$(ALL_SERVICES))

# ---------------------------------------------------------------------------
# Image export targets
# ---------------------------------------------------------------------------
$(IMG_DIR):
	mkdir -p $(IMG_DIR)

$(addprefix image-,$(ALL_SERVICES)): image-%: build-% | $(IMG_DIR)
	podman save localhost/$*:latest | gzip > $(IMG_DIR)/$*.tar.gz
	@echo "Exported: $(IMG_DIR)/$*.tar.gz"

image-postgres: | $(IMG_DIR)
	podman pull $(POSTGRES_IMAGE)
	podman save $(POSTGRES_IMAGE) | gzip > $(IMG_DIR)/postgres.tar.gz
	@echo "Exported: $(IMG_DIR)/postgres.tar.gz"

images: $(addprefix image-,$(ALL_SERVICES)) image-postgres

# ---------------------------------------------------------------------------
# Deploy bundle
# ---------------------------------------------------------------------------
BUNDLE_NAME := deploy-bundle-$(DATE).tar.gz

bundle:
	@mkdir -p $(DIST_DIR)
	tar -czf $(DIST_DIR)/$(BUNDLE_NAME) \
		configs/shared/ \
		configs/prod/images.env \
		quadlet/ \
		scripts/deploy/ \
		scripts/lib.sh \
		scripts/manage-partner-secrets.sh \
		scripts/generate-jwt.sh \
		services/api-user/config/application-prod.yml \
		services/api-order/config/application-prod.yml \
		services/api-product/config/application-prod.yml \
		services/api-auth/config/application-prod.yml \
		services/bff/config/application-prod.yml \
		cockpit/
	@echo "Bundle: $(DIST_DIR)/$(BUNDLE_NAME)"

# ---------------------------------------------------------------------------
# Aggregate
# ---------------------------------------------------------------------------
dist: bundle images

# ---------------------------------------------------------------------------
# Clean
# ---------------------------------------------------------------------------
clean:
	rm -rf $(DIST_DIR)
