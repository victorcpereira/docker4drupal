# ----------------
# Make help script
# ----------------

# Usage:
# Add help text after target name starting with '\#\#'
# A category can be added with @category. Team defaults:
# 	dev-environment
# 	docker
# 	drush

# Output colors
GREEN  := $(shell tput -Txterm setaf 2)
WHITE  := $(shell tput -Txterm setaf 7)
YELLOW := $(shell tput -Txterm setaf 3)
RESET  := $(shell tput -Txterm sgr0)

# Script
HELP_FUN = \
	%help; \
	while(<>) { push @{$$help{$$2 // 'options'}}, [$$1, $$3] if /^([a-zA-Z\-]+)\s*:.*\#\#(?:@([a-zA-Z\-]+))?\s(.*)$$/ }; \
	print "usage: make [target]\n\n"; \
	print "see makefile for additional commands\n\n"; \
	for (sort keys %help) { \
	print "${WHITE}$$_:${RESET}\n"; \
	for (@{$$help{$$_}}) { \
	$$sep = " " x (32 - length $$_->[0]); \
	print "  ${YELLOW}$$_->[0]${RESET}$$sep${GREEN}$$_->[1]${RESET}\n"; \
	}; \
	print "\n"; }

help: ## Show help (same if no target is specified).
	@perl -e '$(HELP_FUN)' $(MAKEFILE_LIST) $(filter-out $@,$(MAKECMDGOALS))

#
# Dev Environment settings
#

include .env

.PHONY: up down stop prune ps shell drush logs help

default: up

DRUPAL_ROOT ?= /var/www/html/docroot

#
# Dev Operations
#
up: ##@docker Start containers and display status.
	@echo "Starting up containers for $(PROJECT_NAME)..."
	docker-compose pull
	docker-compose up -d --remove-orphans
	docker-compose ps

down: stop

stop: ##@docker Stop and remove containers.
	@echo "Stopping containers for $(PROJECT_NAME)..."
	@docker-compose stop

prune: ##@docker Remove containers for project.
	@echo "Removing containers for $(PROJECT_NAME)..."
	@docker-compose down -v

ps: ##@docker List containers.
	@docker ps --filter name='$(PROJECT_NAME)*'

shell: ##@docker Shell into the container. Specify container name.
	docker exec -ti -e COLUMNS=$(shell tput cols) -e LINES=$(shell tput lines) $(shell docker ps --filter name='$(PROJECT_NAME)_php' --format "{{ .ID }}") sh

shell-mysql: ##@docker Shell into mysql container.
	docker exec -ti -e COLUMNS=$(shell tput cols) -e LINES=$(shell tput lines) $(shell docker ps --filter name='$(PROJECT_NAME)_mariadb' --format "{{ .ID }}") sh

drush: ##@docker Run arbitrary drush commands.
	docker exec $(shell docker ps --filter name='$(PROJECT_NAME)_php' --format "{{ .ID }}") drush -r $(DRUPAL_ROOT) $(filter-out $@,$(MAKECMDGOALS))

logs: ##@docker Display log.
	@docker-compose logs -f $(filter-out $@,$(MAKECMDGOALS))

#
# Dev Environment build operations
#
install: ##@dev-environment Configure development environment.
	if [ ! -f .env ]; then cp .env.dist .env; fi
	make down
	make up
	make composer-install
	@echo "Pulling database for $(PROJECT_NAME)..."
	make pull-db
  make prep-site
	@echo "Development environment for $(PROJECT_NAME) is ready."
	make uli

composer-update: ##@dev-environment Run composer update.
	docker-compose exec -T php composer update -n --prefer-dist -vvv

composer-install: ##@dev-environment Run composer install
	docker-compose exec -T php composer install -n --prefer-dist -vvv

pull-db: ##@dev-environment Download AND import `database.sql`.
	if [ -f build/db/database.sql ]; then rm build/db/database.sql; fi
	@echo "\033[1;31mYou need to create the script to Download the database\033[0m"
  make import-db

import-db: ##@dev-environment Import locally cached copy of `database.sql` to project dir.
	@echo "Dropping old database for $(PROJECT_NAME)..."
	docker exec $(shell docker ps --filter name='$(PROJECT_NAME)_php' --format "{{ .ID }}") drush -r $(DRUPAL_ROOT) sql-drop -y
	@echo "Importing database for $(PROJECT_NAME)..."
	pv build/db/database.sql | docker exec -i $(PROJECT_NAME)_mariadb mysql -u$(DB_USER) -p$(DB_PASSWORD) $(DB_NAME)

prep-site: ##@dev-environment Prepare site for local dev.
	@echo "Admin password is set to '1'"
	docker exec $(shell docker ps --filter name='$(PROJECT_NAME)_php' --format "{{ .ID }}") drush -r $(DRUPAL_ROOT) user:password admin "1"

#
# Drush
#
uli: ##drush Generate login link.
	docker exec $(shell docker ps --filter name='$(PROJECT_NAME)_php' --format "{{ .ID }}") drush -r $(DRUPAL_ROOT) --uri='$(PROJECT_BASE_URL)' uli

cim: ##drush Drush import configuration.
	docker exec $(shell docker ps --filter name='$(PROJECT_NAME)_php' --format "{{ .ID }}") drush -r $(DRUPAL_ROOT) config-import

cr: ##drush Drush import configuration.
	docker exec $(shell docker ps --filter name='$(PROJECT_NAME)_php' --format "{{ .ID }}") drush -r $(DRUPAL_ROOT) cc all

cex: ##drush Drush import configuration.
	docker exec $(shell docker ps --filter name='$(PROJECT_NAME)_php' --format "{{ .ID }}") drush -r $(DRUPAL_ROOT) config-export

updb: ##drush run database updates.
	docker exec $(shell docker ps --filter name='$(PROJECT_NAME)_php' --format "{{ .ID }}") drush -r $(DRUPAL_ROOT) updb -v

entup: ##drush run database updates.
	docker exec $(shell docker ps --filter name='$(PROJECT_NAME)_php' --format "{{ .ID }}") drush -r $(DRUPAL_ROOT) entup -v

# https://stackoverflow.com/a/6273809/1826109
%:
	@:
