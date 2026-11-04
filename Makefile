# raize — build, test, and acceptance for the framework.
# Toolchain: a locally built mettle (see notes/HOW-I-VERIFIED.md).
M       ?= ./mettle-build/bin/mettle
BUILD   ?= build
PORT    ?= 8080

APPS    := tasks chat todos
# Fixture apps: tests/fixtures/app/<name>/app.mettle -> build/<name>, checked by
# tests/fixtures/app/<name>/test.sh (tests/integration/apps.sh runs them all).
FIXTURE_APPS := $(notdir $(patsubst %/,%,$(dir $(wildcard tests/fixtures/app/*/app.mettle))))
FRAMEWORK := raize.mettle $(wildcard framework/*/*.mettle) framework/signal/signal.js
MODULES := $(wildcard framework/*/*.mettle) $(wildcard tests/unit/*.mettle)

.PHONY: all clean test lint integration apps apps-release $(APPS) run-% smoke tasks-test ws-test hub-test chat-test signal-test

all: $(APPS)

$(BUILD):
	mkdir -p $(BUILD)

# Every app goes through tools/rzpp: it expands html"""...""" view literals and rz
# decorators (@resource, @signal) into plain Mettle, keeping every line number
# (until the compiler has tagged literals and @generate, DECISIONS.md D1).
$(BUILD)/rzpp: $(wildcard tools/rzpp/*.mettle) $(wildcard framework/str/*.mettle) | $(BUILD)
	$(M) --build tools/rzpp/main.mettle -o $@

%.gen.mettle: %.mettle $(BUILD)/rzpp
	$(BUILD)/rzpp $< $@

.SECONDARY:

$(BUILD)/%: examples/%/app.gen.mettle $(FRAMEWORK) | $(BUILD)
	$(M) --build $< -o $@

$(BUILD)/%: tests/fixtures/app/%/app.gen.mettle $(FRAMEWORK) | $(BUILD)
	$(M) --build $< -o $@

$(BUILD)/release/%: tests/fixtures/app/%/app.gen.mettle $(FRAMEWORK) | $(BUILD)
	mkdir -p $(BUILD)/release
	$(M) --build --release $< -o $@

$(APPS): %: $(BUILD)/%

# Unit tests: each module that declares @test functions runs in the
# compile-time interpreter (no codegen, no sockets).
lint:
	./tests/lint.sh

test: lint
	@fail=0; for f in $(MODULES); do \
	  if grep -q '@test' "$$f"; then \
	    echo "== $$f"; \
	    $(M) test "$$f" || fail=1; \
	  fi; \
	done; exit $$fail

smoke: $(BUILD)/tasks
	./tests/integration/tasks.sh $(BUILD)/tasks $(PORT)

tasks-test: $(BUILD)/tasks
	./tests/integration/tasks.sh $(BUILD)/tasks 8081
	./tests/integration/leak.sh $(BUILD)/tasks 8081 2000
	./tests/integration/config.sh $(BUILD)/tasks 8082

# Fixture apps (tests/fixtures/app/*/test.sh), debug; apps-release builds --release.
apps: $(BUILD)/rzpp $(addprefix $(BUILD)/,$(FIXTURE_APPS))
	./tests/integration/apps.sh $(BUILD)

apps-release: $(BUILD)/rzpp $(addprefix $(BUILD)/release/,$(FIXTURE_APPS))
	./tests/integration/apps.sh $(BUILD)/release

# Everything, in order: layout, unit, then the HTTP and WebSocket suites.
integration: test $(BUILD)/tasks $(BUILD)/chat $(BUILD)/todos $(BUILD)/ws_echo $(BUILD)/hub_app $(BUILD)/rzpp $(addprefix $(BUILD)/,$(FIXTURE_APPS))
	./tests/integration/tasks.sh $(BUILD)/tasks 8080
	./tests/integration/http_edges.sh $(BUILD)/tasks 8080
	./tests/integration/leak.sh $(BUILD)/tasks 8080 2000
	./tests/integration/config.sh $(BUILD)/tasks 8082
	./tests/integration/ws.sh $(BUILD)/ws_echo 8095
	./tests/integration/ws.sh $(BUILD)/hub_app 8097 http
	./tests/integration/chat.sh $(BUILD)/chat 8090
	./tests/integration/rzpp.sh $(BUILD)/rzpp
	./tests/integration/signal.sh $(BUILD)/todos 8070
	./tests/integration/apps.sh $(BUILD)

# WebSockets on the epoll loop (needs the dev compiler's syscall builtin).
$(BUILD)/ws_echo: tests/fixtures/poll/ws_echo.mettle $(wildcard framework/*/*.mettle) | $(BUILD)
	$(M) --build $< -o $@

ws-test: $(BUILD)/ws_echo
	./tests/integration/ws.sh $(BUILD)/ws_echo 8095

# The same checks through the real server: router -> rz_hub_upgrade -> hub.
$(BUILD)/hub_app: tests/fixtures/hub/app.mettle $(wildcard framework/*/*.mettle) | $(BUILD)
	$(M) --build $< -o $@

hub-test: $(BUILD)/hub_app
	./tests/integration/ws.sh $(BUILD)/hub_app 8097 http

# Signals: rzpp diagnostics, then examples/todos driven like signal.js.
signal-test: $(BUILD)/rzpp $(BUILD)/todos
	./tests/integration/rzpp.sh $(BUILD)/rzpp
	./tests/integration/signal.sh $(BUILD)/todos 8070

# Phoenix channels: examples/chat driven by a v2-protocol client.
chat-test: $(BUILD)/chat
	./tests/integration/chat.sh $(BUILD)/chat 8090

run-%: $(BUILD)/%
	./$(BUILD)/$*

clean:
	rm -rf $(BUILD)
