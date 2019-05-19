#!/usr/bin/env bash

sed -i -- "s/^[\t ]*listen.*$/listen ${PORT};/" /etc/nginx/nginx.conf
