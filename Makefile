# raize — build, test, and acceptance for the framework.
# Toolchain: a locally built mettle (see notes/HOW-I-VERIFIED.md).
M       ?= ./mettle-build/bin/mettle
BUILD   ?= build
PORT    ?= 8080

APPS    := hello site
MODULES := $(wildcard framework/*/*.mettle) $(wildcard tests/unit/*.mettle)

.PHONY: all clean test lint integration $(APPS) run-% smoke site-test

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

smoke: $(BUILD)/hello
	./tests/integration/smoke.sh $(BUILD)/hello $(PORT)

site-test: $(BUILD)/site
	./tests/integration/site.sh $(BUILD)/site 8081
	./tests/integration/leak.sh $(BUILD)/hello 8080 2000
	./tests/integration/leak.sh $(BUILD)/site 8081 2000
	./tests/integration/config.sh $(BUILD)/hello 8082

# Everything, in order: layout, unit, then the two HTTP suites.
integration: test $(BUILD)/hello $(BUILD)/site
	./tests/integration/smoke.sh $(BUILD)/hello 8080
	./tests/integration/http_edges.sh $(BUILD)/hello 8080
	./tests/integration/site.sh $(BUILD)/site 8081
	./tests/integration/leak.sh $(BUILD)/hello 8080 2000
	./tests/integration/leak.sh $(BUILD)/site 8081 2000
	./tests/integration/config.sh $(BUILD)/hello 8082

run-%: $(BUILD)/%
	./$(BUILD)/$*

clean:
	rm -rf $(BUILD)
