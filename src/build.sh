#!/bin/bash

set -e
set -x

env | sort
nice -n 15 ./mach build
./mach buildsymbols
./mach package
rsync -a obj-firefox/dist/firefox-*.tar.* /dist/
chmod 0666 /dist/*
