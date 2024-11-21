#!/bin/bash

set -e

bash ./adguardhome.sh
bash ./nginx.sh $@