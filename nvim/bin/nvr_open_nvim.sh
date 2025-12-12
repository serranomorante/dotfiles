#!/usr/bin/env bash

FILENAME="/$(echo $* | cut -d / -f 4-)"
kitty-open-in-editor $FILENAME
