#!/bin/sh
cd single
pkill 'etcd'
nohup etcd &
nohup ./kvrocks &
export ETCDCTL_API=3
etcdctl --endpoints=http://127.0.0.1:2379 put /serverlist/1 '{"name":"鸿蒙初开","opentime":"2024-08-01","status":"火爆"}'
etcdctl --endpoints=http://127.0.0.1:2379 put /serverlist/2 '{"name":"盘古开天","opentime":"2025-08-01","status":"火爆"}'
etcdctl --endpoints=http://127.0.0.1:2379 put /service/db/capacity 1
etcdctl --endpoints=http://127.0.0.1:2379 put /service/db/instance/0 127.0.0.1:6666
etcdctl --endpoints=http://127.0.0.1:2379 put /service/gateway/instance/0 127.0.0.1:10001
etcdctl --endpoints=http://127.0.0.1:2379 put /service/role/capacity 1
etcdctl --endpoints=http://127.0.0.1:2379 put /service/role/instance/0 127.0.0.1:10002
