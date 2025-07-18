CC = clang

BUILD_DIR := build

all: $(patsubst %.ll,$(BUILD_DIR)/%,$(wildcard *.ll))

$(BUILD_DIR)/%: %.ll | $(BUILD_DIR)
	$(CC) $< -o $@

%: $(BUILD_DIR)/%

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

clean:
	rm -r $(BUILD_DIR)

.PHONY: clean all
