#txTrader Makefile

THIS_FILE := $(lastword $(MAKEFILE_LIST))

REQUIRED_PACKAGES = daemontools-run ucspi-tcp python python-dev
REQUIRED_PIP = pytest Twisted hexdump ujson simplejson requests pytz tzlocal ../IbPy/dist/*.tar.gz ./dist/*.tar.gz

#PYTHON = /usr/bin/python
ENVDIR = /etc/txtrader
PYTHON = python2
PIP = pip2
VENV = $(HOME)/venv/txtrader

# mode can be: tws cqg rtx
MODE=rtx

# set account to AUTO for make testconfig to auto-set demo account
TEST_HOST = 127.0.0.1
TEST_PORT = 7497 
TEST_ACCOUNT = AUTO

default:
	@echo "\nQuick Start Commands:\n\nsudo make clean && sudo make config && make build && make venv && sudo make install && make run\n"

clean:
	@echo "Cleaning up..."
	rm -f txtrader/*.pyc
	rm -rf build
	rm -rf dist 
	rm -rf $(VENV)
	rm -f .make-*

build:  .make-build

.make-build: .make-config setup.py txtrader/*.py
	@echo "Building..."
	python bumpbuild.py
	python setup.py sdist 
	touch .make-build

config: .make-config

.make-config:
	@echo "Configuring..."
	@getent >/dev/null passwd txtrader && echo "User txtrader exists." || adduser --gecos "" --home / --shell /bin/false --no-create-home --disabled-login txtrader
	@for package in $(REQUIRED_PACKAGES); do \
	  dpkg-query >/dev/null -l $$package && echo "verified package $$package" || break;\
	done;
	mkdir -p $(ENVDIR)
	chmod 770 $(ENVDIR)
	cp -r etc/txtrader/* $(ENVDIR)
	echo $(VENV)>etc/txtrader/TXTRADER_VENV
	chown -R txtrader.txtrader $(ENVDIR)
	chmod 640 $(ENVDIR)/*
	touch .make-config

testconfig:
	@echo "Configuring test API..."
	$(MAKE) start
	sudo sh -c "echo $(TEST_PORT)>$(ENVDIR)/TXTRADER_API_PORT"
	sudo sh -c "echo $(TEST_ACCOUNT)>$(ENVDIR)/TXTRADER_API_ACCOUNT"
	@echo -n "Restarting service..."
	@sudo svc -t /etc/service/txtrader
	@while [ "$$(txtrader 2>/dev/null $(MODE) status)" != "Connected" ]; do echo -n .;sleep 1; done;
	@txtrader $(MODE) status
	@if [ "$(TEST_ACCOUNT)" = "AUTO" ]; then\
          echo -n "Getting account...";\
	  while [ "$$(txtrader 2>/dev/null $(MODE) query_accounts)" = "[]" ]; do echo -n .;sleep 1; done;\
	  echo OK;\
	  export ACCOUNT="`txtrader $(MODE) query_accounts | tr -d \"[]\'\" | cut -d, -f1`";\
	else\
	  export ACCOUNT="$(TEST_ACCOUNT)";\
	fi;\
	echo "Setting test ACCOUNT=$$ACCOUNT";\
	sudo sh -c "echo $$ACCOUNT>$(ENVDIR)/TXTRADER_API_ACCOUNT";\

venv:	.make-venv

.make-venv:
	@echo "(re)configure venv"
	rm -rf $(VENV)
	virtualenv -p $(PYTHON) $(VENV)
	. $(VENV)/bin/activate; \
	for package in $(REQUIRED_PIP); do \
          echo -n "Installing package $$package into virtual env..."; $(PIP) install $$package || false;\
        done;
	echo $(VENV) >$(ENVDIR)/TXTRADER_VENV
	touch .make-venv

install: .make-venv config
	@echo "Installing txtrader..."
	cp bin/txtrader /usr/local/bin/txtrader
	mkdir -p /var/svc.d
	rm -rf /var/svc.d/txtrader
	cp -rp service/txtrader /var/svc.d
	touch /var/svc.d/txtrader/down
	chown -R root.root /var/svc.d/txtrader
	chown root.txtrader /var/svc.d/txtrader
	chown root.txtrader /var/svc.d/txtrader/*.tac
	update-service --add /var/svc.d/txtrader

start:
	@echo "Starting Service..."
	sudo rm -f /etc/service/txtrader/down
	sudo svc -u /etc/service/txtrader

stop:
	@echo "Stopping Service..."
	sudo touch /etc/service/txtrader/down
	sudo svc -d /etc/service/txtrader

restart: stop start
	@echo "Restarting Service..."

uninstall:
	@echo "Uninstalling..."
	if [ -e /etc/service/txtrader ]; then\
	  svc -d /etc/service/txtrader;\
	  svc -d /etc/service/txtrader/log;\
	  update-service --remove /var/svc.d/txtrader;\
	fi
	rm -rf /var/svc.d/txtrader
	cat files.txt | xargs rm -f
	rm -f /usr/local/bin/txtrader

TESTS := $(wildcard txtrader/*_test.py)

TPARM := 

.PHONY: test 

test: $(TESTS)
	@echo Testing...
	. $(VENV)/bin/activate && cd txtrader; envdir ../etc/txtrader env TXTRADER_TEST_MODE=$(MODE) py.test -svx $(TPARM) $(notdir $^)

run: 
	@echo Running...
	. $(VENV)/bin/activate && envdir etc/txtrader twistd --reactor=poll --nodaemon --logfile=- --pidfile= --python=service/txtrader/txtrader.tac
