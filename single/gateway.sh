#!/bin/sh
./silly/silly ./app/main.lua --etcd=127.0.0.1:2379 --listen="127.0.0.1:10001" --service="gateway" --loglevel="debug"
