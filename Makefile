# raize — build, test, and acceptance for the framework.
# Toolchain: a locally built mettle (see notes/HOW-I-VERIFIED.md).
M       ?= ./mettle-build/bin/mettle
BUILD   ?= build
PORT    ?= 8080

APPS    := tasks chat
MODULES := $(wildcard framework/*/*.mettle) $(wildcard tests/unit/*.mettle)

.PHONY: all clean test lint integration $(APPS) run-% smoke tasks-test ws-test hub-test chat-test

all: $(APPS)

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/%: examples/%/app.mettle | $(BUILD)
	$(M) --build $< -o $@

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

# Everything, in order: layout, unit, then the HTTP and WebSocket suites.
integration: test $(BUILD)/tasks $(BUILD)/chat $(BUILD)/ws_echo $(BUILD)/hub_app
	./tests/integration/tasks.sh $(BUILD)/tasks 8080
	./tests/integration/http_edges.sh $(BUILD)/tasks 8080
	./tests/integration/leak.sh $(BUILD)/tasks 8080 2000
	./tests/integration/config.sh $(BUILD)/tasks 8082
	./tests/integration/ws.sh $(BUILD)/ws_echo 8095
	./tests/integration/ws.sh $(BUILD)/hub_app 8097 http
	./tests/integration/chat.sh $(BUILD)/chat 8090

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

# Phoenix channels: examples/chat driven by a v2-protocol client.
chat-test: $(BUILD)/chat
	./tests/integration/chat.sh $(BUILD)/chat 8090

run-%: $(BUILD)/%
	./$(BUILD)/$*

clean:
	rm -rf $(BUILD)
