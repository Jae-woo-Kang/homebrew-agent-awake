.PHONY: test build install clean

test:
	swift test
	bash -n Sources/AgentAwake/Resources/agentawake-guardian.sh
	ruby -c Casks/agent-awake.rb

build:
	VERSION=0.1.0 scripts/build-app.sh

install: build
	scripts/install-local.sh

clean:
	rm -rf .build .build-universal dist
