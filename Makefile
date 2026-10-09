.PHONY: test lint check install uninstall clean mascot

test:
	bats tests/

lint:
	shellcheck nudge.sh install.sh uninstall.sh setup.sh lib/*.sh
	shellcheck -s bash --severity=warning -e SC2034,SC2123,SC2088 tests/*.bats

check: lint test

install:
	./install.sh

uninstall:
	./uninstall.sh

clean:
	rm -rf tests/tmp/

mascot:
	docs/assets/make-mascot.sh
