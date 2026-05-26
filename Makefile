TARGET := bin/hrm
SRC := hrm/hrm.pas

FPC ?= fpc
FPCFLAGS ?= -O3 -XX -Xs

PREFIX ?= /usr/local
BINDIR := $(DESTDIR)$(PREFIX)/bin

USER_CONFIG_HOME ?= $(HOME)/.config
USER_SFX_DIR := $(USER_CONFIG_HOME)/hrm/SFX

.PHONY: all clean run install uninstall install-user-sfx install-bin

all: $(TARGET)

$(TARGET): $(SRC)
	mkdir -p bin
	$(FPC) $(FPCFLAGS) -o$(TARGET) $(SRC)

run: $(TARGET)
	./$(TARGET) --help

install: install-user-sfx install-bin

install-bin: $(TARGET)
	install -d $(BINDIR)
	install -Dm755 $(TARGET) $(BINDIR)/hrm

install-user-sfx:
	install -d $(USER_CONFIG_HOME)/hrm
	rm -rf $(USER_SFX_DIR)
	cp -R SFX $(USER_SFX_DIR)

uninstall:
	rm -f $(BINDIR)/hrm
	rm -rf $(USER_CONFIG_HOME)/hrm

clean:
	rm -rf bin
	rm -f hrm/*.o hrm/*.ppu hrm/*.or hrm/*.res
