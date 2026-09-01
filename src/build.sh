#!/bin/bash

set -e
set -x

env | sort
nice -n 15 ./mach build
echo -e "#define MOZ_SOURCE_STAMP $(git log -1 --format="%H")" >>/src/firefox/obj-firefox/browser/installer/../../source-repo.h
# ./mach buildsymbols
./mach package
rsync -a obj-firefox/dist/firefox-*.tar.* /dist/
chmod 0666 /dist/*
