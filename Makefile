.PHONY: up check

include .env.prod

IMAGE ?= tulibraries/isilon_tracker
VERSION ?= $(DOCKER_IMAGE_VERSION)
HARBOR ?= harbor.k8s.temple.edu
BASE_IMAGE ?= harbor.k8s.temple.edu/library/ruby:3.4-alpine
PLATFORM ?= linux/x86_64
CLEAR_CACHES ?= no
SECRET_KEY_BASE ?= $(ISILON_TRACKER_SECRET_KEY_BASE)
CI ?= false
ISILON_TRACKER_DB_HOST ?= host.docker.internal
ISILON_TRACKER_DB_USER ?= postgres

DEFAULT_RUN_ARGS ?= -e "EXECJS_RUNTIME=Disabled" \
		-e "K8=yes" \
		-e "RAILS_ENV=production" \
		-e "SECRET_KEY_BASE=$(SECRET_KEY_BASE)" \
		-e "RAILS_SERVE_STATIC_FILES=yes" \
		-e "RAILS_LOG_TO_STDOUT=yes" \
		--rm -it

build:
	@docker build --build-arg RAILS_MASTER_KEY=$(RAILS_MASTER_KEY) \
		--build-arg SECRET_KEY_BASE=$(SECRET_KEY_BASE) \
		--build-arg BASE_IMAGE=$(BASE_IMAGE) \
		--platform $(PLATFORM) \
		--progress plain \
		--tag $(HARBOR)/$(IMAGE):$(VERSION) \
		--tag $(HARBOR)/$(IMAGE):latest \
		--file .docker/app/Dockerfile \
		--no-cache .

run:
	@docker run --name=isilon_tracker -p 127.0.0.1:3001:3000/tcp \
		--platform $(PLATFORM) \
		$(DEFAULT_RUN_ARGS) \
		$(HARBOR)/$(IMAGE):$(VERSION)

lint:
	@if [ $(CI) == false ]; \
		then \
			hadolint .docker/app/Dockerfile; \
		fi

scan:
	@if [ $(CLEAR_CACHES) == yes ]; \
		then \
			trivy image --scanners vuln  -c $(HARBOR)/$(IMAGE):$(VERSION); \
		fi
	@if [ $(CI) == false ]; \
		then \
			trivy image --scanners vuln $(HARBOR)/$(IMAGE):$(VERSION); \
		fi

deploy: scan lint
	@docker push $(HARBOR)/$(IMAGE):$(VERSION) \
	# This "if" statement needs to be a one liner or it will fail.
	# Do not edit indentation
	@if [ $(VERSION) != latest ]; \
		then \
			docker push $(HARBOR)/$(IMAGE):latest; \
		fi

up: 
	bundle install
	bundle exec rake db:setup
	bundle exec rake db:migrate
	bundle exec rails s -d -p 3000
