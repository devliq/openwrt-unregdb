VERSION ?= 9999.0001-r1
.PHONY: all db packages feed check publish clean keys

all: db

db: dist/regulatory.db

dist/regulatory.db: build.py
	python3 build.py -o $@

packages: db
	VERSION=$(VERSION) sh scripts/build-packages.sh

feed: db
	VERSION=$(VERSION) sh scripts/build-feed.sh

check: feed
	python3 build.py -o /tmp/regulatory.db
	cmp dist/regulatory.db /tmp/regulatory.db
	./scripts/build-usign.sh >/dev/null
	$$(./scripts/build-usign.sh) -V -p keys/unregdb.pub \
		-m dist/opkg/Packages -x dist/opkg/Packages.sig

publish: feed
	sh scripts/publish.sh

keys:
	sh scripts/gen-keys.sh

clean:
	rm -rf dist .cache
