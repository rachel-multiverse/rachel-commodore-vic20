# Rachel VIC-20 Client Makefile
# Uses cc65 toolchain (ca65 assembler, ld65 linker)

CA65 ?= ca65
LD65 ?= ld65

BUILD_DIR = build
SRC_DIR = src
ASM_SOURCES = $(wildcard $(SRC_DIR)/*.asm $(SRC_DIR)/net/*.asm $(SRC_DIR)/solo/*.asm $(SRC_DIR)/solo/fixtures/*.asm)

TARGET = $(BUILD_DIR)/rachel.prg
MAP = $(BUILD_DIR)/rachel.map
E2E_TARGET = $(BUILD_DIR)/rachel-e2e.prg
E2E_OBJECT = $(BUILD_DIR)/main-e2e.o
SOLO_SPIKE_TARGET = $(BUILD_DIR)/rachel-solo-kernel-spike.prg
SOLO_SPIKE_OBJECT = $(BUILD_DIR)/main-solo-kernel-spike.o

# VIC-20 with 8KB expansion config
CONFIG = vic20-8k.cfg

.PHONY: all test asm198x-check solo-kernel-spike solo-kernel-e2e e2e-prg e2e-full-game e2e-full-game-ntsc e2e-eight-player e2e-reconnect capture-video release clean

all: $(BUILD_DIR) $(TARGET)
	@echo "Built: $(TARGET)"
	@ls -la $(TARGET)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/main.o: $(ASM_SOURCES)
	$(CA65) -t vic20 -o $@ $(SRC_DIR)/main.asm

$(TARGET): $(BUILD_DIR)/main.o $(CONFIG)
	$(LD65) -C $(CONFIG) -o $@ -m $(MAP) $(BUILD_DIR)/main.o vic20.lib

test: all
	python3 tests/test_protocol.py
	python3 tests/solo_kernel.py
	python3 tests/check_memory_budget.py
	python3 tests/check_assembly_quality.py

# AS198X may be either an installed binary or a path supplied by the caller.
AS198X ?= asm198x
asm198x-check: $(BUILD_DIR)
	$(AS198X) asm --dialect ca65 src/asm198x.asm -o $(BUILD_DIR)/rachel-asm198x.bin \
		--sym=$(BUILD_DIR)/rachel-asm198x.sym \
		--debug=$(BUILD_DIR)/rachel-asm198x.debug198x

solo-kernel-spike: $(BUILD_DIR) $(SOLO_SPIKE_TARGET)

solo-kernel-e2e: solo-kernel-spike
	python3 tests/solo_kernel_e2e.py

$(SOLO_SPIKE_OBJECT): $(ASM_SOURCES)
	$(CA65) -t vic20 -D SOLO_KERNEL_TEST=1 -o $@ $(SRC_DIR)/main.asm

$(SOLO_SPIKE_TARGET): $(SOLO_SPIKE_OBJECT) $(CONFIG)
	$(LD65) -C $(CONFIG) -o $@ -Ln $(BUILD_DIR)/solo-kernel-spike.lbl $< vic20.lib

e2e-prg: $(BUILD_DIR) $(E2E_TARGET)

e2e-full-game: e2e-prg
	python3 tests/full_game_e2e.py

e2e-full-game-ntsc: e2e-prg
	RACHEL_E2E_REGION=ntsc RACHEL_E2E_OUTPUT=e2e-output-ntsc \
	python3 tests/full_game_e2e.py

e2e-eight-player: e2e-prg
	RACHEL_E2E_MIN_PLAYERS=8 RACHEL_E2E_AI_PLAYERS=7 \
	RACHEL_E2E_GAME_FRAMES=90000 RACHEL_E2E_OUTPUT=e2e-output-8 \
	python3 tests/full_game_e2e.py

e2e-reconnect: e2e-prg
	RACHEL_E2E_DROP_AFTER_SERVER_FRAMES=10 RACHEL_E2E_GAME_FRAMES=60000 \
	RACHEL_E2E_WRITE_INTERVAL=300ms \
	RACHEL_E2E_OUTPUT=e2e-output-reconnect \
	python3 tests/full_game_e2e.py

capture-video: e2e-prg
	python3 tests/capture_video.py

release: test
	python3 scripts/package_release.py

$(E2E_OBJECT): $(ASM_SOURCES)
	$(CA65) -t vic20 -D E2E_AUTOPLAY=1 -o $@ $(SRC_DIR)/main.asm

$(E2E_TARGET): $(E2E_OBJECT) $(CONFIG)
	$(LD65) -C $(CONFIG) -o $@ $(E2E_OBJECT) vic20.lib

clean:
	rm -rf $(BUILD_DIR)
