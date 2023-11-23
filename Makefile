SHELL := /bin/bash

SRC_DOCS := $(wildcard src/*.md)
SRC_CSS := css/pandoc.css

BUILD_DOCS := $(addprefix build/,$(notdir $(SRC_DOCS:.md=.html)))
BUILD_CSS := $(addprefix build/css/,$(notdir $(SRC_CSS)))
PANDOC := pandoc

PANDOC_OPTIONS := -t markdown-smart --standalone
PANDOC_HTML_OPTIONS := --to html5 --css $(SOURCE_CSS)
PANDOC_COMMAND = $(PANDOC) $(PANDOC_OPTIONS) $(PANDOC_HTML_OPTIONS)

.PHONY: all
all: $(BUILD_DOCS)

build:
	mkdir -p build/css

build/index.html: src/index.md $(BUILD_CSS) | build
	$(PANDOC_COMMAND) -s $< -o $@

build/%.html: src/%.md $(BUILD_CSS) | build
	$(PANDOC_COMMAND) -s $< -o $@

build/css/%.css: css/%.css | build
	cp $< $@

.PHONY: install
install: all
	mkdir -p /var/www/mmynk.com
	rm -rf /var/www/mmynk.com/*
	[[ -d /var/www/mmynk.com/css ]] || mkdir /var/www/mmynk.com/css
	cp -r build/* /var/www/mmynk.com/

.PHONY: clean
clean:
	rm -rf build
