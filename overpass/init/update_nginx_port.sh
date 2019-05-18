#!/usr/bin/env bash

sed -i -- "s/^[\t ]*listen.*$/listen ${PORT};/" nginx.conf

