SHELL := /bin/sh
.SHELLFLAGS := -ec
.DELETE_ON_ERROR:

TESTS := $(wildcard tests/test_*.lua)
aseprite ?= aseprite
REBUILD_ASSETS ?= 0
asset_source = $(if $(filter 1,$(REBUILD_ASSETS)),$(1))
LOVE_VERSION ?= 0.10.2
LOVE_DOWNLOAD_URL ?= https://github.com/love2d/love/releases/download/$(LOVE_VERSION)

APPNAME = Quadtastic
APPIDENTIFIER = com.25a0.quadtastic
APPVERSION ?= $(shell git describe --tags --always 2>/dev/null || printf 'dev')
APPCOPYRIGHT = 2017-2018 Moritz Neikes
macos-love-distname = love-$(LOVE_VERSION)-macosx-x64
windows-love-distname = love-$(LOVE_VERSION)-win32

# When changing these edition identifiers, remember to change them in strings.lua
EDITION_WINDOWS = windows
EDITION_MACOS = osx
EDITION_CROSSPLATFORM = love
EDITION_LIBQUADTASTIC = libquadtastic

.PHONY: clean test check run all distfiles app_resources run_debug windows macos linux crossplatform $(TESTS)

all: run_debug

run: app_resources
	${DEBUG} love ${APPNAME}

run_debug: DEBUG=DEBUG=true
run_debug: run

LICENSES = LICENSE.txt ${APPNAME}/res/copyright.txt ${APPNAME}/libquadtastic.lua
SHARED_FILES := $(shell find shared -type f | sed 's/ /\\ /g')

APP_RESOURCES = ${LICENSES} \
				${APPNAME}/res/m5x7.ttf \
				${APPNAME}/res/m3x6.ttf \
				${APPNAME}/res/loading.png \
                ${APPNAME}/res/style.png \
                ${APPNAME}/res/icon-32x32.png \
                ${APPNAME}/res/turboworkflow-deactivated.png \
                ${APPNAME}/res/turboworkflow-activated.png \
                ${APPNAME}/res/version.txt

app_resources: ${APP_RESOURCES}

DISTFILES = dist/releases/${APPVERSION}/windows/${APPNAME}.zip \
			dist/releases/${APPVERSION}/macos/${APPNAME}.zip \
			dist/releases/${APPVERSION}/linux/${APPNAME}.tar.gz \
            dist/releases/${APPVERSION}/crossplatform/${APPNAME}.zip \
            dist/releases/${APPVERSION}/love/${APPNAME}.love \
            dist/releases/${APPVERSION}/libquadtastic/libquadtastic.lua

distfiles: ${DISTFILES}

windows: dist/releases/${APPVERSION}/windows/${APPNAME}.zip
macos: dist/releases/${APPVERSION}/macos/${APPNAME}.zip
linux: dist/releases/${APPVERSION}/linux/${APPNAME}.tar.gz
crossplatform: dist/releases/${APPVERSION}/crossplatform/${APPNAME}.zip

dist/releases/${APPVERSION}/macos/${APPNAME}.zip: dist/macos/${APPNAME}.zip
	mkdir -p "$(@D)"
	cp "$<" "$@"

dist/releases/${APPVERSION}/linux/${APPNAME}.tar.gz: dist/${APPNAME}.love Makefile
	rm -rf dist/linux/${APPNAME}
	mkdir -p dist/linux/${APPNAME} "$(@D)"
	cp dist/${APPNAME}.love LICENSE.txt dist/linux/${APPNAME}/
	printf '%s\n' '#!/bin/sh' 'cd "$$(dirname "$$0")" || exit 1' 'exec love ./$(APPNAME).love "$$@"' > dist/linux/${APPNAME}/${APPNAME}
	chmod +x dist/linux/${APPNAME}/${APPNAME}
	printf '%s\n' 'Requires LOVE $(LOVE_VERSION) and LuaFileSystem for Lua 5.1 installed by your distribution.' 'Run ./$(APPNAME) to start. This archive does not bundle a Linux runtime.' > dist/linux/${APPNAME}/README.txt
	tar -czf "$@" -C dist/linux ${APPNAME}

dist/releases/${APPVERSION}/windows/${APPNAME}.zip: dist/windows/${APPNAME}.zip
	mkdir -p dist/releases/${APPVERSION}/windows
	cp dist/windows/${APPNAME}.zip dist/releases/${APPVERSION}/windows/

dist/releases/${APPVERSION}/crossplatform/${APPNAME}.zip: dist/${APPNAME}.love $(SHARED_FILES) Makefile
	mkdir -p dist/releases/${APPVERSION}/crossplatform
	rm -rf dist/crossplatform
	mkdir -p dist/crossplatform
	cp dist/${APPNAME}.love LICENSE.txt dist/crossplatform/
	cp -R shared dist/crossplatform/
	rm -f "$@"
	cd dist/crossplatform; zip -q -r -0 ../releases/${APPVERSION}/crossplatform/${APPNAME}.zip .

dist/releases/${APPVERSION}/love/${APPNAME}.love: dist/${APPNAME}.love $(SHARED_FILES) Makefile
	mkdir -p dist/releases/${APPVERSION}/love
	cp dist/${APPNAME}.love dist/releases/${APPVERSION}/love/
	mkdir -p dist/releases/${APPVERSION}/love/shared
	cp -R shared/. dist/releases/${APPVERSION}/love/shared/

dist/releases/${APPVERSION}/libquadtastic/libquadtastic.lua: Quadtastic/libquadtastic.lua
	mkdir -p dist/releases/${APPVERSION}/libquadtastic
	cp Quadtastic/libquadtastic.lua dist/releases/${APPVERSION}/libquadtastic/

APP_SOURCES := $(shell find ${APPNAME} -type f ! -path '*/.*' ! -name version.txt ! -name edition.txt)

.PHONY: dist_shared
dist_shared:
	mkdir -p dist/shared
	cp -R shared/. dist/shared/

dist/${APPNAME}.love: ${APP_SOURCES} ${APP_RESOURCES} Makefile | dist_shared
	mkdir -p dist
	rm -rf dist/love
	cp -R ${APPNAME} dist/love
	printf '%s\n' ${EDITION_CROSSPLATFORM} > dist/love/res/edition.txt
	rm -f "$@"
	cd dist/love; zip -q -r -0 ../${APPNAME}.love . -x '.*' '*/.*'

dist/windows/${APPNAME}.zip: dist/res/${windows-love-distname}.zip dist/${APPNAME}.love shared/Windows/lfs.dll Makefile
	rm -rf dist/windows/${APPNAME} dist/windows/runtime
	mkdir -p dist/windows/${APPNAME}
	unzip -q dist/res/${windows-love-distname}.zip -d dist/windows/runtime
	cp -R dist/windows/runtime/${windows-love-distname}/. dist/windows/${APPNAME}/
	cp dist/${APPNAME}.love dist/windows/

	# Update edition in this version of the .love archive
	mkdir -p dist/windows/res
	echo ${EDITION_WINDOWS} > dist/windows/res/edition.txt
	cd dist/windows; zip ${APPNAME}.love -Z store res/edition.txt
	rm dist/windows/res/edition.txt
	rm -d dist/windows/res

	cat dist/windows/${APPNAME}/love.exe dist/windows/${APPNAME}.love > dist/windows/${APPNAME}/${APPNAME}.exe
	rm dist/windows/${APPNAME}.love
	rm dist/windows/${APPNAME}/love.exe
	mkdir -p dist/windows/${APPNAME}/shared/Windows
	cp shared/Windows/* dist/windows/${APPNAME}/shared/Windows/
	cp LICENSE.txt dist/windows/${APPNAME}/Quadtastic-LICENSE.txt
	rm -f "$@"
	cd dist/windows/${APPNAME}; zip -q -r -0 ../${APPNAME}.zip .

dist/res/${windows-love-distname}.zip dist/res/${macos-love-distname}.zip:
	mkdir -p dist/res
	curl --fail --location --retry 3 "$(LOVE_DOWNLOAD_URL)/$(@F)" -o "$@.tmp"
	unzip -tq "$@.tmp"
	mv "$@.tmp" "$@"

dist/macos/${APPNAME}.zip: dist/res/${macos-love-distname}.zip dist/${APPNAME}.love $(SHARED_FILES) Makefile
	@test -x /usr/libexec/PlistBuddy || { echo 'The macOS target requires macOS (PlistBuddy).'; exit 1; }
	@test -f 'shared/OS X/lfs.so' || { echo 'Missing shared/OS X/lfs.so for the macOS runtime.'; exit 1; }
	rm -rf dist/macos
	mkdir -p dist/macos
	unzip -q dist/res/${macos-love-distname}.zip -d dist/macos
	mv dist/macos/love.app dist/macos/${APPNAME}.app
	cp dist/${APPNAME}.love dist/macos/${APPNAME}.app/Contents/Resources/${APPNAME}.love
	mkdir -p dist/macos/edition/res
	printf '%s\n' ${EDITION_MACOS} > dist/macos/edition/res/edition.txt
	cd dist/macos/edition; zip -q -0 ../${APPNAME}.app/Contents/Resources/${APPNAME}.love res/edition.txt
	mkdir -p 'dist/macos/${APPNAME}.app/Contents/Resources/shared/OS X'
	cp 'shared/OS X/'* 'dist/macos/${APPNAME}.app/Contents/Resources/shared/OS X/'
	mkdir -p 'dist/macos/${APPNAME}.app/Contents/MacOS/shared/OS X'
	cp 'shared/OS X/'* 'dist/macos/${APPNAME}.app/Contents/MacOS/shared/OS X/'
	/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier ${APPIDENTIFIER}' dist/macos/${APPNAME}.app/Contents/Info.plist
	/usr/libexec/PlistBuddy -c 'Set :CFBundleName ${APPNAME}' dist/macos/${APPNAME}.app/Contents/Info.plist
	/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString $(patsubst v%,%,${APPVERSION})' dist/macos/${APPNAME}.app/Contents/Info.plist
	cp LICENSE.txt dist/macos/Quadtastic-LICENSE.txt
	cd dist/macos; zip -q -y -r -0 ${APPNAME}.zip ${APPNAME}.app Quadtastic-LICENSE.txt

dist/res/%.icns: res/%.ase
	mkdir -p dist/res
	cp res/$*.ase dist/res/
	# Create iconset folder with icon at various sizes
	./scale_icon.sh dist/res/$*.ase
	# Run iconutil to create icns file
	iconutil -c icns dist/res/$*.iconset

screenshots/turboworkflow.gif: res/turboworkflow-activated.ase Makefile
	${aseprite} -b res/turboworkflow-activated.ase --scale 1 --save-as screenshots/turboworkflow.gif

${APPNAME}/res/turboworkflow-activated.png: $(call asset_source,res/turboworkflow-activated.ase)
	${aseprite} -b res/turboworkflow-activated.ase --sheet ${APPNAME}/res/turboworkflow-activated.png

${APPNAME}/res/loading.png: $(call asset_source,res/loading.ase)
	${aseprite} -b res/loading.ase --sheet ${APPNAME}/res/loading.png

${APPNAME}/res/%.png: $(call asset_source,res/%.ase)
	${aseprite} -b res/$*.ase --save-as ${APPNAME}/res/$*.png

${APPNAME}/res/icon-32x32.png: $(call asset_source,res/icon.ase)
	${aseprite} -b res/icon.ase --scale 2 --save-as ${APPNAME}/res/icon-32x32.png

# hacky way to determine whether we need to remake the version file
_stored_version = $(shell test -f ${APPNAME}/res/version.txt && cat ${APPNAME}/res/version.txt)
ifneq "v$(patsubst v%,%,$(APPVERSION))" "$(_stored_version)"
.PHONY: ${APPNAME}/res/version.txt
endif

${APPNAME}/res/version.txt:
	printf '%s\n' v$(patsubst v%,%,$(APPVERSION)) > ${APPNAME}/res/version.txt

%.png: %.ase
	${aseprite} -b $*.ase --save-as $*.png

%.gif: %.mov
	mkdir -p .tmp
	ffmpeg -i $*.mov -r 10 -vcodec png .tmp/out-static-%04d.png 
	time convert -verbose +dither -alpha set -layers Optimize .tmp/out-static*.png  GIF:- > $*.gif
	rm .tmp/out-static-*

test check: $(TESTS)

$(TESTS):
	lua $@

clean:
	rm -rf dist/

firstyear=2017
thisyear=$(shell date "+%Y")
years=$(shell test ${firstyear} = ${thisyear} && echo ${firstyear} || echo ${firstyear}-${thisyear})

# hacky way to determine whether we need to remake the license file
_remake_license = $(shell test -f LICENSE.txt && grep -q " ${years} " LICENSE.txt || echo 1)
ifeq "${_remake_license}" "1"
.PHONY: LICENSE.txt
endif

LICENSE.txt: res/raw_mit_license.txt
	sed -e 's/\[years\]/${years}/' $< > $@

${APPNAME}/res/copyright.txt: LICENSE.txt
	head -1 LICENSE.txt > ${APPNAME}/res/copyright.txt

# hacky way to determine whether we need to remake the license file
_remake_libquadtastic = $(shell grep -q " ${years} " Quadtastic/libquadtastic.lua || echo 1)
ifeq "1" "${_remake_libquadtastic}"
.PHONY: ${APPNAME}/libquadtastic.lua
endif

${APPNAME}/libquadtastic.lua:
	sed -e 's/Copyright (c) .* Moritz Neikes/Copyright (c) ${years} Moritz Neikes/' $@ > $@.tmp
	mv $@.tmp $@

# Build as $ make release-0.2.0
# Tag names MUST follow the major.minor.patch pattern.
release-%: test ${LICENSES} ${DISTFILES}
	@# Only allow releases from the master branch.
	@git status -b --porcelain | head -n 1 | grep --silent "## master" || \
	(echo "Error: Can only release from master"; exit 1)

	@# Only allow releasing a clean working directory
	@test -z "`git status --porcelain --untracked-files=no`" || \
	(echo "Error: Working directory is not clean"; exit 1)

	@# Check whether there are any files in the archive that are not in the
	@# index
	@mkdir -p .tmp
	@# This writes all files in the index to indexed_files.txt that are in
	@# Quadtastic, or in any subdirectory
	@cd Quadtastic; git ls-files . | sort > ../.tmp/indexed_files.txt
	@# This writes all files in the zipfile to staged_files.txt.
	@# We explicitly remove res/version.txt since we need that file to be in
	@# the archive, but not in the index
	@# We also remove any directories listed in the zip, since they will not
	@# show up in the index.
	@unzip -Z -1 dist/${APPNAME}.love | \
	grep -v "res/version.txt" - | \
	grep -v "/$$" - | \
	sort > .tmp/staged_files.txt
	@-diff .tmp/staged_files.txt .tmp/indexed_files.txt > .tmp/filelists.diff
	@test -s .tmp/filelists.diff && \
	echo "Error: ${APPNAME}.love includes files that are not in the index:" && \
	cat .tmp/filelists.diff && \
	echo "Remove these files or add them to the index; then re-make all distfiles" && \
	false || true

	@# Only proceed if that version doesn't already exist
	@test ! -f .git/refs/tags/$* || \
	(echo "Error: Version $* is already released"; exit 1)

	# Check that the version to be released is tagged.
	@if [[ ! $* =~ ^[0-9]+.[0-9]+.[0-9]+$$ ]] ; then\
	  echo "Error: Version does not have major.minor.patch format."; false;\
	fi

	@printf "\e[1mReleasing $*\e[0m\n"
	@printf "Press CTRL-C at any time to cancel the release\n"

	@# Prepare tag message
	@mkdir -p .tmp
	@echo 'Release $*\n' > .tmp/tagmessage

	@printf "\e[1m1. Write release message\e[0m\n"
	@printf "\
	# Write a message for release $*\n\
	# Lines starting with # will be ignored\n\n\
	" >> .tmp/tagmessage
	@echo "Changelog:" >> .tmp/tagmessage

	@################################################################
	@# If you're on linux, you will almost certainly need to change #
	@# `sed -E` to `sed -r`. Sorry for that                         #
	@################################################################
	@cat changelog.md | sed -E '/^### Unreleased/,/^### Release/!d' \
					  | sed -E '/^###/d' >> .tmp/tagmessage

	@# Open the tag message in the editor before creating the tag.
	@# If you're using sublime text as your editor, make sure to pass the -w
	@# flag so that sublime text doesn't return until you close the edited
	@# tag message.
	@${EDITOR} .tmp/tagmessage
	@cp .tmp/tagmessage .tmp/releasemessage

	@# Now we use the composed tag message to update the changelog, so that
	@# changelog and release notes are uniform.
	@sed -i '' "/^#.*/ d" .tmp/releasemessage
	@sed -i '' "/Changelog:/ d" .tmp/releasemessage

	@# Can't use multi-line sed commands in Make, so this is stored separately
	@./changelog.sh $*

	@#Now combine all of this to update the changelog
	@sed -E '1,/### Unreleased/ !d' < changelog.md > .tmp/planned
	@sed -E '/### Release/,$$ !d' < changelog.md > .tmp/older
	@cat -s .tmp/planned .tmp/releasemessage .tmp/older > .tmp/changelog

	@printf "\e[1m2. Review new changelog\e[0m\n"
	@${EDITOR} .tmp/changelog
	@printf "\e[1m3. Commit changes to changelog\e[0m\n"
	@cp .tmp/changelog changelog.md
	git add -p changelog.md

	git commit -m "Update changelog.md"

	@# Signing tag
	@printf "\e[1m4. Tag release\e[0m\n"
	@git tag -s $* -F .tmp/tagmessage

	@# Merge master into stable
	@printf "\e[1m4. Merge master branch into stable branch\e[0m\n"
	git checkout stable
	git merge --ff-only master
	git checkout master

	@rm -rf .tmp
	@printf "\e[1mAll done.\e[0m You can now run 'make publish' to publish version $*\n"
	@printf "Remember to push the new tag, as well as the master and stable branch.\n"


