CC = clang
CFLAGS = -O3 -mavx512f -march=native 

BUILD_DIR := build

all: $(patsubst %.ll,$(BUILD_DIR)/%,$(wildcard *.ll))

$(BUILD_DIR)/%: %.ll | $(BUILD_DIR)
	$(CC) $(CFLAGS) $< -o $@

%: $(BUILD_DIR)/%

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

clean:
	rm -r $(BUILD_DIR)

.PHONY: clean all
