.PHONY: test lint install uninstall clean

test:
	bats tests/

lint:
	shellcheck nudge.sh install.sh uninstall.sh setup.sh lib/*.sh

install:
	./install.sh

uninstall:
	./uninstall.sh

clean:
	rm -rf tests/tmp/
