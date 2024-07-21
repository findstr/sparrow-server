#!/bin/sh
cd server
./silly/silly ./app/main.lua --etcd=127.0.0.1:2379 --listen="127.0.0.1:10002" --service="role" --workerid=0
