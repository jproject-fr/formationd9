include .env

default: up

## CONTAINERS variables
COMPOSER_ROOT ?= /var/www/html
DRUPAL_ROOT ?= /var/www/html/web
DRUPAL_DEFAULT ?= web/sites/default

## help	:	Print commands help.
.PHONY: help
ifneq (,$(wildcard docker.mk))
help : docker.mk
	@sed -n 's/^##//p' $<
else
help : Makefile
	@sed -n 's/^##//p' $<
endif

## up	:	Start up containers.
.PHONY: up
up:
	@echo "Starting up containers for $(PROJECT_NAME)..."
	docker-compose pull
	docker-compose up -d --remove-orphans

.PHONY: mutagen
mutagen:
	docker-compose up -d mutagen
	mutagen project start -f mutagen/config.yml

## down	:	Stop containers.
.PHONY: down
down: stop

## start	:	Start containers without updating.
.PHONY: start
start:
	@echo "Starting containers for $(PROJECT_NAME) from where you left off..."
	@docker-compose start

## stop	:	Stop containers.
.PHONY: stop
stop:
	@echo "Stopping containers for $(PROJECT_NAME)..."
	@docker-compose stop

## prune	:	Remove containers and their volumes.
##		You can optionally pass an argument with the service name to prune single container
##		prune mariadb	: Prune `mariadb` container and remove its volumes.
##		prune mariadb solr	: Prune `mariadb` and `solr` containers and remove their volumes.
.PHONY: prune
prune:
	@echo "Removing containers for $(PROJECT_NAME)..."
	@docker-compose down -v $(filter-out $@,$(MAKECMDGOALS))

## ps	:	List running containers.
.PHONY: ps
ps:
	@docker ps --filter name='$(PROJECT_NAME)*'

## shell	:	Access `php` container via shell.
##		You can optionally pass an argument with a service name to open a shell on the specified container
.PHONY: shell
shell:
	docker exec -ti -e COLUMNS=$(shell tput cols) -e LINES=$(shell tput lines) $(shell docker ps --filter name='$(PROJECT_NAME)_$(or $(filter-out $@,$(MAKECMDGOALS)), 'php')' --format "{{ .ID }}") sh

## composer	:	Executes `composer` command in a specified `COMPOSER_ROOT` directory (default is `/var/www/html`).
##		To use "--flag" arguments include them in quotation marks.
##		For example: make composer "update drupal/core --with-dependencies"
.PHONY: composer
composer:
	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_php' --format "{{ .ID }}") composer --working-dir=$(COMPOSER_ROOT) $(filter-out $@,$(MAKECMDGOALS))

## drush	:	Executes `drush` command in a specified `DRUPAL_ROOT` directory (default is `/var/www/html/web`).
##		To use "--flag" arguments include them in quotation marks.
##		For example: make drush "watchdog:show --type=cron"
.PHONY: drush
drush:
	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_php' --format "{{ .ID }}") drush -r $(DRUPAL_ROOT) $(filter-out $@,$(MAKECMDGOALS))

## logs	:	View containers logs.
##		You can optinally pass an argument with the service name to limit logs
##		logs php	: View `php` container logs.
##		logs nginx php	: View `nginx` and `php` containers logs.
.PHONY: logs
logs:
	@docker-compose logs -f $(filter-out $@,$(MAKECMDGOALS))

# https://stackoverflow.com/a/6273809/1826109
%:
	@:

##########################################################################
##    Specific to project
##########################################################################

BLACK        := $(shell tput -Txterm setaf 0)
RED          := $(shell tput -Txterm setaf 1)
GREEN        := $(shell tput -Txterm setaf 2)
YELLOW       := $(shell tput -Txterm setaf 3)
LIGHTPURPLE  := $(shell tput -Txterm setaf 4)
PURPLE       := $(shell tput -Txterm setaf 5)
BLUE         := $(shell tput -Txterm setaf 6)
WHITE        := $(shell tput -Txterm setaf 7)

RESET := $(shell tput -Txterm sgr0)

# Shortcut for Drush command inside the container (this allows to handle --parameter with no errors).
DRUSHCOMMAND := docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_php' --format "{{ .ID }}") drush -r $(DRUPAL_ROOT)

## local-env	:	Rename files for local environment.
.PHONY: local-env
local-env: local-settings
	@echo "${BLUE}Copy .env.example to .env${RESET}"
	@cp -i .env.example .env && echo "${GREEN}File created.${RESET}" || echo "${RED}File not created.${RESET}"
	@echo "${BLUE}Copy docker-compose.override.example.yml docker-compose.override.yml${RESET}"
	@cp -i docker-compose.override.example.yml docker-compose.override.yml && echo "${GREEN}File created.${RESET}" || echo "${RED}File not created.${RESET}"

## local-settings : Copy the example.settings.local.php to settings.local.php in sites/default
.PHONY: local-settings
local-settings:
	@echo "Copy the example.settings.local.php to settings.local.php in sites/default"
	@chmod 755 ${DRUPAL_DEFAULT} # Drupal set the default directory to read-only, we need to make it writable
	@cp -i web/sites/example.settings.local.php ${DRUPAL_DEFAULT}/settings.local.php && echo "${GREEN}File created.${RESET}" || echo "${RED}File not created.${RESET}"
	@chmod 555 ${DRUPAL_DEFAULT} # Revert permissions

## fix-permissions : Allow you to change folder permissions (555 on sites/default and 777 for underneath folders)
.PHONY: fix-permissions
fix-permissions:
	@find ${DRUPAL_DEFAULT} -type d -exec chmod --changes 777 {} \;
	@chmod 555 ${DRUPAL_DEFAULT}
	@chmod 444 ${DRUPAL_DEFAULT}/settings.php

## init	:	Install drupal with your code configuration set.
.PHONY: init
init:
	@echo "${BLUE}Installing Drupal...${RESET}"
	${DRUSHCOMMAND} si minimal --account-name=${DRUPAL_INIT_ADMIN_USER_NAME} --account-pass=${DRUPAL_INIT_ADMIN_PASSWORD} --account-mail=${DRUPAL_INIT_ADMIN_EMAIL}
	@echo "${BLUE}Update site variables...${RESET}"
	${DRUSHCOMMAND} cset "system.site" uuid "06f43768-9b03-4511-b081-0bd609c9e7b7"
	@echo "${BLUE}Run Update DB hooks - Drush updb ...${RESET}"
	${DRUSHCOMMAND} updb
	@echo "${BLUE}Import config${RESET}"
	${DRUSHCOMMAND} cim
	@echo "${BLUE}Install theme...${RESET}"
	make theme
	@echo "${BLUE}Clear cache - Drush cr ...${RESET}"
	make drush cr
	@echo "${GREEN}BOUYAKAAAA !!! Run ${RED}make website ${GREEN}to launch your website${RESET}"

## import-db	:	Save your current database, then Executes drush sql-cli<db.sql command in php container.
.PHONY: import-db
import-db:
	@echo "${BLUE}Dumping current database as a backup...${RESET}"
	@${DRUSHCOMMAND} sql-dump --result-file=../db-backup.sql
	@echo "${BLUE}Empty all tables...${RESET}"
	@${DRUSHCOMMAND} sql-drop
	@echo "${BLUE}Importing databse with drush...${RESET}"
	@${DRUSHCOMMAND} sql-cli<db.sql && echo "${GREEN}Databse Imported. You can remove the db.sql file now.${RESET}" || echo "${RED}You need a db.sql file at the root of the project.${RESET}"

## export-db	:	Save your current database, then Executes drush sql-cli<db.sql command in php container.
.PHONY: export-db
export-db:
	@echo "${BLUE}Dumping current database as a backup...${RESET}"
	@${DRUSHCOMMAND} sql-dump --result-file=../db-backup.sql && echo "${GREEN}Database Exported : db-backup.sql.${RESET}" || echo "${RED}Exporting database failed.${RESET}"

.PHONY: backup-db
backup-db:
	@echo "${BLUE}Making a backup of the database${RESET}"
	@mkdir -p backups/databases
	@${DRUSHCOMMAND} sql-dump --result-file=../backups/databases/db-backup-$(shell date +%FT%T%Z).sql && echo "${GREEN}Database successfully exported to your backups/databases directory.${RESET}" || echo "${RED}Exporting database failed.${RESET}"

## theme	:	Executes `npm install` command in the main theme directory locally.
.PHONY: theme
theme:
	@echo "${BLUE}Starting npm install on drupal theme${RESET}"
	docker-compose exec node npm install
	@echo "${BLUE}Webpack...${RESET}"
	make webpack-compile-prod

## website	:	Launch website in default browser.
.PHONY: website
website:
	xdg-open http://${PROJECT_BASE_URL} || open http://${PROJECT_BASE_URL}

## adminer	:	Launch adminer in default browser.
.PHONY: adminer
adminer:
	xdg-open http://adminer.${PROJECT_BASE_URL} || open http://adminer.${PROJECT_BASE_URL}

## import-trans : Check, download, and import or update Drupal translations (custom or from drupal.org)
.PHONY: import-trans
import-trans:
	@echo "${BLUE}Check available Drupal translations...${RESET}"
	@${DRUSHCOMMAND} locale-check
	@echo "${BLUE}Update Drupal translations...${RESET}"
	@${DRUSHCOMMAND} locale-update
	@${DRUSHCOMMAND} locale:import zh-hans ../translations/drupal-8.9.12.zh-hans.po

## update	:	Executes some drush commands to update the database.
.PHONY: update
update: backup-db
	@echo "${BLUE}Run composer install ...${RESET}"
	make composer install
	@echo "${BLUE}Removing Elastic Search Index config file to avoid AWS Elastic Search timeout, it will be re-imported with local config during drush cim command ...${RESET}"
	@make drush cdel elasticsearch_connector.cluster.local
	@echo "${BLUE}Run Update DB hooks - Drush updb ...${RESET}"
	make drush updb
	@echo "${BLUE}Run Drush SQL Sanitize to anonymize user data - Drush sql:sanitize ...${RESET}"
	make drush sql:sanitize
	@echo "${BLUE}Clear cache - Drush cr BEFORE cim ...${RESET}"
	make drush cr
	@echo "${BLUE}Import config - Drush cim ...${RESET}"
	make drush cim
	@echo "${BLUE}Clear cache - Drush cr AFTER cim ...${RESET}"
	make drush cr
	@echo "${BLUE}Run webpack updates ...${RESET}"
	make theme

## update	:	Executes some drush commands to update the database with no backup and no webpack, and no sanitize.
.PHONY: update-quick
update-quick:
	@echo "${BLUE}Run composer install ...${RESET}"
	make composer install
	@echo "${BLUE}Removing Elastic Search Index config file to avoid AWS Elastic Search timeout, it will be re-imported with local config during drush cim command ...${RESET}"
	@make drush cdel elasticsearch_connector.cluster.local
	@echo "${BLUE}Run Update DB hooks - Drush updb ...${RESET}"
	make drush updb
	@echo "${BLUE}Clear cache - Drush cr BEFORE cim ...${RESET}"
	make drush cr
	@echo "${BLUE}Import config - Drush cim ...${RESET}"
	make drush cim
	@echo "${BLUE}Clear cache - Drush cr AFTER cim ...${RESET}"
	make drush cr

## code-check : Run code style check on current modified files.
.PHONY: code-check
code-check:
	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_php' --format "{{ .ID }}") grumphp git:pre-commit $(filter-out $@,$(MAKECMDGOALS))

## code-fix :  Run PHPCS fix (see phpcbf) on current modified files.
.PHONY: code-fix
code-fix:
	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_php' --format "{{ .ID }}") phpcbf '--standard=Drupal,DrupalPractice' '--extensions=php,module,inc,install,test,profile,theme,css,info,txt,md' '--report=full' '--ignore=.github,.gitlab,bower_components,node_modules,vendor' $(filter-out $@,$(MAKECMDGOALS))

.PHONY: node-shell
node-shell:
	docker-compose exec node bash

.PHONY: webpack-compile-dev
webpack-compile-dev:
	docker-compose exec node npm run dev

.PHONY: webpack-compile-prod
webpack-compile-prod:
	docker-compose exec node npm run prod

.PHONY: webpack-watch
webpack-watch:
	docker-compose exec node npm run watch

.PHONY: webpack-serve
webpack-serve:
	docker-compose exec node npm run start

.PHONY: get-private-files
get-private-files:
	rsync -rzv -e 'ssh -A -J develop@pp-jump.dev.hautehorlogerie.cloud' develop@pp-wawo21front.server.aws.richemont.com:~/preprod/web/shared/private-files .
	rsync -rzv -e 'ssh -A -J develop@pp-jump.dev.hautehorlogerie.cloud' develop@pp-wawo21front.server.aws.richemont.com:~/preprod/web/shared/files web/sites/default

.PHONY: uli
uli:
	docker-compose exec php bash -c "drush uli --uri=https://genevaww.localhost"
