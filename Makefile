# raize — build, test, and acceptance for the framework.
# Toolchain: a locally built mettle (see notes/HOW-I-VERIFIED.md).
M       ?= ./mettle-build/bin/mettle
BUILD   ?= build
PORT    ?= 8080

APPS    := tasks
MODULES := $(wildcard framework/*/*.mettle) $(wildcard tests/unit/*.mettle)

.PHONY: all clean test lint integration $(APPS) run-% smoke tasks-test

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

# Everything, in order: layout, unit, then the HTTP suites.
integration: test $(BUILD)/tasks
	./tests/integration/tasks.sh $(BUILD)/tasks 8080
	./tests/integration/http_edges.sh $(BUILD)/tasks 8080
	./tests/integration/leak.sh $(BUILD)/tasks 8080 2000
	./tests/integration/config.sh $(BUILD)/tasks 8082

run-%: $(BUILD)/%
	./$(BUILD)/$*

clean:
	rm -rf $(BUILD)
