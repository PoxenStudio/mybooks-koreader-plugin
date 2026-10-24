PLUGIN   := mybooks.koplugin
NAME     := mybooks
VERSION  := $(shell sed -n 's/.*version *= *"\([^"]*\)".*/\1/p' $(PLUGIN)/_meta.lua)
DIST     := dist
ZIP      := $(DIST)/$(NAME)_koplugin_$(VERSION).zip

SOURCES  := $(shell find $(PLUGIN) -type f)

.PHONY: all zip clean

all: zip

zip: $(ZIP)

$(ZIP): $(SOURCES)
	@mkdir -p $(DIST)
	@rm -f $@
	@zip -r $@ $(PLUGIN) >/dev/null
	@echo "Generated $@"

clean:
	@rm -rf $(DIST)
	@echo "Cleaned $(DIST)"
