#!/bin/bash

# format date string
DATESTR=$(date '+%Y%m%d')
ETCDCTL_DIR=/tmp/etcd-download-test

# backup etcd
ETCDCTL_API=3 ${ETCDCTL_DIR}/etcdctl --endpoints=https://127.0.0.1:2379 \
--cacert=/etc/kubernetes/pki/etcd/ca.crt \
--cert=/etc/kubernetes/pki/etcd/server.crt \
--key=/etc/kubernetes/pki/etcd/server.key \
snapshot save /home/kraken/etcd-backup/etcd-backup-${DATESTR}.bkp
