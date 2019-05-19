#!/usr/bin/env bash

sed -i -- "s/^[\t ]*listen.*$/listen ${PORT};/" /etc/nginx/nginx.conf
sed -i -- "s/^[\t ]*fastcgi_pass.*$/fastcgi_pass 127.0.0.1:12345;/" /etc/nginx/nginx.conf