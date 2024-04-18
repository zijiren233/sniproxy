#!/bin/bash

set -e

bash ./adguardhome.sh
bash ./sniproxy.sh
bash ./nginx.sh
