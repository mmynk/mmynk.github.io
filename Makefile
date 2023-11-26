SHELL := /bin/bash

SRC_DOCS := $(wildcard src/*.md)
SRC_BIO_DOCS := $(wildcard src/biohacking/*.md)
SRC_CSS := /css/pandoc.css

BUILD_DOCS := $(addprefix build/,$(notdir $(SRC_DOCS:.md=.html))) $(addprefix build/biohacking/,$(notdir $(SRC_BIO_DOCS:.md=.html)))
BUILD_CSS := $(addprefix build/css/,$(notdir $(SRC_CSS)))
PANDOC := pandoc

PANDOC_OPTIONS := --standalone --to html5 --css $(SRC_CSS) --include-in-header header.html
PANDOC_COMMAND := $(PANDOC) $(PANDOC_OPTIONS)

.PHONY: all
all: $(BUILD_DOCS)

build:
	mkdir -p build/css
	mkdir -p build/biohacking
	cp assets/* build/

build/index.html: src/index.md $(BUILD_CSS) | build
	$(PANDOC_COMMAND) -s $< -o $@

build/%.html: src/%.md $(BUILD_CSS) | build
	$(PANDOC_COMMAND) -s $< -o $@

build/biohacking/%.html: src/biohacking/%.md $(BUILD_CSS) | build
	$(PANDOC_COMMAND) -s $< -o $@

build/css/%.css: css/%.css | build
	cp $< $@

.PHONY: clean
clean:
	rm -rf build
