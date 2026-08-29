# Rachel VIC-20 Client Makefile
# Uses cc65 toolchain (ca65 assembler, ld65 linker)

CA65 ?= ca65
LD65 ?= ld65

BUILD_DIR = build
SRC_DIR = src

TARGET = $(BUILD_DIR)/rachel.prg
MAP = $(BUILD_DIR)/rachel.map

# VIC-20 with 8KB expansion config
CONFIG = vic20-8k.cfg

.PHONY: all test clean

all: $(BUILD_DIR) $(TARGET)
	@echo "Built: $(TARGET)"
	@ls -la $(TARGET)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/main.o: $(SRC_DIR)/main.asm $(SRC_DIR)/*.asm $(SRC_DIR)/net/*.asm
	$(CA65) -t vic20 -o $@ $(SRC_DIR)/main.asm

$(TARGET): $(BUILD_DIR)/main.o $(CONFIG)
	$(LD65) -C $(CONFIG) -o $@ -m $(MAP) $(BUILD_DIR)/main.o vic20.lib

test: all
	python3 tests/test_protocol.py

clean:
	rm -rf $(BUILD_DIR)
