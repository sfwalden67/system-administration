#!/usr/bin/env bash
set -e

dataDir='/data/azure-t7a-fs'
azureCredsDir='/etc/azure-smb-credentials'
fileshare='//<AZURE_SERVER>/<AZURE_FILESHARENAME>'
shareName='<AZURE_FILESHARENAME>'

echo "unmounting $dataDir"
if [ -d "$dataDir" ]; then
sudo umount $dataDir || echo "$dataDir already unmounted"
fi


echo "removing $dataDir do you want to continue (y/n)?"
read answer
if [ "$answer" !=  "${answer#[Yy]}" ]; then
    sudo rm -rf $dataDir
else
  echo "exiting... not removing $dataDir"
  exit 1
fi

echo "removing credentials dir $azureCredsDir"
sudo rm -rf $azureCredsDir

echo "removing /etc/fstab share entry $fileshare"
sed -i "/$shareName/d" /etc/fstab

echo "unmount finished."