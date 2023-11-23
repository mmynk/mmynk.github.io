SHELL := /bin/bash

SRC_DOCS := $(wildcard src/*.md)

BUILD_DOCS := $(addprefix build/,$(notdir $(SRC_DOCS:.md=.html)))
PANDOC := pandoc

PANDOC_HTML_OPTIONS := --standalone --to html5
PANDOC_COMMAND = $(PANDOC) $(PANDOC_HTML_OPTIONS)

.PHONY: all
all: $(BUILD_DOCS)

build:
	mkdir -p build

build/index.html: src/index.md | build
	$(PANDOC_COMMAND) -s $< -o $@

build/%.html: src/%.md | build
	$(PANDOC_COMMAND) -s $< -o $@

.PHONY: install
install: all
	mkdir -p /var/www/mmynk.com
	rm -rf /var/www/mmynk.com/*
	cp -r build/* /var/www/mmynk.com/

.PHONY: clean
clean:
	rm -rf build
