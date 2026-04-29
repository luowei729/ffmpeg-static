.PHONY: build deps clean

build:
	./scripts/build.sh

deps:
	sudo ./scripts/install-build-deps.sh

clean:
	rm -rf work dist
