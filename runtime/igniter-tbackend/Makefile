.PHONY: build run test verify-auth verify-core docker-build docker-up docker-down package bundle-macos clean-proof

build:
	cargo build --release --bin tbackend

run: build
	./target/release/tbackend --config tbackend.config.json

test:
	cargo test

verify-auth: build
	ruby scripts/verify/verify_auth.rb

verify-core: test verify-auth

docker-build:
	docker build -t tbackend:0.1.0-lab.1-local .

docker-up:
	docker compose -f docker-compose.quickstart.yml up --build -d

docker-down:
	docker compose -f docker-compose.quickstart.yml down -v

package:
	./scripts/build-and-package.sh

bundle-macos:
	./scripts/build-macos-bundle.sh

clean-proof:
	rm -rf *_data *_daemon.log auth_data auth_off_data data out tbackend.log tbackend.pid tbackend.wal
