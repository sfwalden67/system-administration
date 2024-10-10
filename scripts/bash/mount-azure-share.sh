
dataDir='/data/azure-fileshare'
azureCredsDir='/etc/azure-smb-credentials'
azureCreds="$azureCredsDir/azurefileshare.cred"
fileshare='//<AZURE_SERVER_NAME>/<AZURE_FILESHARE_NAME>'

azureStorageToken=$1
[ -z "$azureStorageToken" ] &&  echo "storage token required to mount $fileshare @ $dataDir" && exit 1

if [ ! -d "$dataDir" ]; then
sudo mkdir $dataDir
fi

if [ ! -d "$azureCredsDir" ]; then
sudo mkdir $azureCredsDir
fi

sudo rm $azureCreds
if [ ! -f "$azureCreds" ]; then
    sudo bash -c "echo 'username=<USSERNAME>' >> $azureCreds"
    sudo bash -c "echo 'password=$azureStorageToken' >> $azureCreds"
fi
sudo chmod 600 $azureCreds

case $(grep "$fileshare" /etc/fstab >/dev/null; echo $?) in
  0)
  echo "NOT adding network mount $bteT7aShare to /etc/fstab"
  ;;
  1)
  echo "adding network mount $fileshare to /etc/fstab"
  sudo bash -c "echo '$fileshare $dataDir cifs nofail,vers=3.0,credentials=$azureCreds,dir_mode=0777,file_mode=0777,serverino' >> /etc/fstab"
  ;;

esac

sudo yum install -y cifs-utils
sudo mount -t cifs $fileshare $dataDir -o vers=3.0,credentials=$azureCreds,dir_mode=0777,file_mode=0777,serverino

echo "mount successful"
ls $dataDir