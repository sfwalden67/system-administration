# Running Kubernetes on Azure

## Step 1: Disable Swap
As of writing, Kubernetes requires that Swap is disabled on the Linux server. This is so that the kubelet process can reliably schedule memory to the pods. To disable swap, run the following command:

```
sudo swapoff -a
```
To make the change permanent, you will need to edit the fstab file.

Open /etc/fstab, remove the line containing swap and then save the file.

```
/dev/mapper/rhel_rhel01-swap none                    swap    defaults        0 0
```
This will prevent swap from being enabled the next time the system boots.

## Step 2: Configure iptables to see bridged traffic.

```
# Create the .conf file to load the modules at bootup
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Set up required sysctl params, these persist across reboots.
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sudo sysctl --system
```

## Step 3: Open Firewall Ports
Run the following commands to open the required ports on the firewall.

```
sudo firewall-cmd --zone=public --add-service=kube-apiserver --permanent
sudo firewall-cmd --zone=public --add-service=etcd-client --permanent
sudo firewall-cmd --zone=public --add-service=etcd-server --permanent
# kubelet-admin-server
sudo firewall-cmd --zone=public --add-port=6443/tcp --permanent
# kubelet API
sudo firewall-cmd --zone=public --add-port=10250/tcp --permanent
sudo firewall-cmd --zone=public --add-port=10255/tcp --permanent
# kube-scheduler
sudo firewall-cmd --zone=public --add-port=10251/tcp --permanent
# kube-controller-manager
sudo firewall-cmd --zone=public --add-port=10252/tcp --permanent
# NodePort Services
sudo firewall-cmd --zone=public --add-port=30000-32767/tcp --permanent
# Nginx
sudo firewall-cmd --zone=public --add-port=10254/tcp --permanent (for the liveness probe)
sudo firewall-cmd --zone=public --add-port=8443/tcp --permanent
sudo firewall-cmd --zone=public --add-port=443/tcp --permanent
# Calico etcd server client API
sudo firewall-cmd --zone=public --add-port=2379-2380/tcp --permanent
# Calico BGP network (only required if the BGP backend is used, bidirectional)
sudo firewall-cmd --zone=public --add-port=179/tcp --permanent
# Calico Typha required ports
sudo firewall-cmd --zone=public --add-port=5473/tcp --permanent
# Calico VXLAN required ports (required bidirectional)
sudo firewall-cmd --zone=public --add-port=4789/udp --permanent
# Postgres (required only if there will be a postgres pod)
sudo firewall-cmd --zone=public --add-port=5432/tcp --permanent
# Enable masquerade for the public zone
sudo firewall-cmd --zone=public --add-masquerade --permanent
# apply changes
sudo firewall-cmd --reload
```

## Step 4: Set SELinux to Permissive
```
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
```
To verify:
```
$ getenforce
Permissive
$ sestatus
SELinux status:                 enabled
SELinuxfs mount:                /sys/fs/selinux
SELinux root directory:         /etc/selinux
Loaded policy name:             targeted
Current mode:                   permissive
Mode from config file:          permissive
Policy MLS status:              enabled
Policy deny_unknown status:     allowed
Memory protection checking:     actual (secure)
Max kernel policy version:      31
```

## Step 5: Install required packages
The latest version of kubernetes available from oracle 8 repos is currently v1.25.7 (but will install 1.25.X containers up to latest stable)
RPM packages are provided for this version located in a zip file on the NextGenDataSysDesign2 share:

There are two repository outlines provided in the repositories directory. Choose the one that is correct for your version of Oracle Linux (7.9 or 8.X). The \<DSS SERVICE TOKEN\> variable needs to be populated with the actual token. Once done, copy the repo file to /etc/yum.repos.d/ on the target machine.

A base installation requires the following (along with all of their dependencies):
```
sudo yum install cri-o kubectl kubeadm kubelet kubernetes-cni libcgroup libcgroup-tools kernel-uek kernel-uek-doc
sudo reboot
```

## Step 6: Verify conmon executables exist
Verify that /usr/libexec/crio/conmon exists and that there is a symbolic link from /bin/conmon pointing to it:
```
$ which conmon
/bin/conmon
$ ls -lah /bin/conmon
lrwxrwxrwx. 1 root root 24 Apr 19 14:34 /bin/conmon -> /usr/libexec/crio/conmon
```

If there is an issue with the symlink, make it:
```
sudo ln -s $(which conmon) /usr/libexec/crio/conmon
```

## Step 7: Enable cgroupfs
```
sudo systemctl enable --now cgconfig
```

## Step 8: Start cri-o service
```
sudo systemctl enable --now crio
sudo systemctl start crio
```

## Step 9: Generate auth base64 key to registry
On your dev vm run:
```
docker --config ./docker-config login sres.web.boeing.com -u dss-service
```
Go to gitlab/song and ci/cd env vars and grab the API key from the
DSS_SERVICE_TOKEN variable. Enter this for the password.

This will now create a folder called docker-config

Inside that folder will be a config.json.

We will also log into the registry to make pulls work for both repos

docker --config ./docker-config login registry.web.boeing.com -u <your bems>

Enter your password for gitlab.

This will now append the gitlab registry auth token to the same config.json in the docker-config folder.

This file now needs to be copied to the target box
into a directory. It is fine to leave it in the kraken user home dir. Create a folder there called
global_auth_files and copy the config.json into it. Once copied, run chmod 666 on the file to make
it accessible to all users.

Also, you will need a base64 encoded version of this entire file. For that, run:
```
base64 config.json >> config_base64
```
keep the config_base64 contents for later

## Step 10: Configure docker repositories
Edit the file in /etc/containers/registries.conf
- Comment out [[registries.search]] and the line underneath
- Comment out [[registries.insecure]] and the line underneath
- Comment out [[registries.block]] and the line underneath
- Leave unqualified-search-registries
- Add the following:
```
[[registry]]
prefix = "registry.web.boeing.com"
insecure = true
location = "registry.web.boeing.com"

[[registry]]
prefix = "sres.web.boeing.com:5000"
insecure = true
location = "sres.web.boeing.com:5000"
```

## Step 11: Get image versions required
Once everything is set up, run:
```
$ kubeadm config images list
# You will see something like this:
[kraken@krakenetes ~]$ kubeadm config images list
I0410 15:13:40.669625 2708018 version.go:256 remote version is much newer: v1.26.3; falling back to: stable-1.25
registry.k8s.io/kube-apiserver:v1.25.8
registry.k8s.io/kube-controller-manager:v1.25.8
registry.k8s.io/kube-scheduler:v1.25.8
registry.k8s.io/kube-proxy:v1.25.8
registry.k8s.io/pause:3.8
registry.k8s.io/etcd:3.5.6-0
registry.k8s.io/coredns/coredns:v1.9.3
```
Take a note of all of these versions. They are required in step 8.1 and step 13

## Step 12: Configure cri-o
Edit the file in /etc/crio/crio.conf
Verify the cgroup_manager is set to "cgroupfs":
```
# Cgroup management implementation used for the runtime.
cgroup_manager = "cgroupfs"
```
Then underneath, add:
```
conmon_cgroup = "pod"
```
At the bottom under
```
# Paths to directories where CNI plugin binaries are located.
plugin_dirs = [
  "/opt/cni/bin",
]
```
Delete the pause_image_auth_file entry and add:
```
[crio.image]
pause_image="sres.web.boeing.com:5000/pause:<VERSION FROM ABOVE>
global_auth_file="/home/kraken/global_auth_files/config.json" <OR WHATEVER DIRECTORY YOU PUT THE SRES AUTH JSON>
```

## Step 13: Disable the default crio bridge
If the file exists, remove /etc/cni/net.d/100-crio-bridge.conf

The reason we are removing this file is that we will be using calico's built in CNI bridge (with VXLAN) instead of cri-o's built in CNI bridge.

## Step 13.1: Make sure the directory /var/lib/crio exists
If the directory does not exist:
```
sudo mkdir /var/lib/crio
```

## Step 14: restart cri-o service for changes to take effect
```
sudo service crio restart
```

## Step 15: configure kubeadm to use cgroupfs
```
sudo vim /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
```
Change systemd to cgroupfs:
```
Environment="KUBELET_CGROUP_ARGS=--cgroup-driver=cgroupfs"
```

## Step 16: Start kubelet service
```
sudo systemctl enable --now kubelet
sudo systemctl start kubelet
```

## Step 17: Create a kubeadm config file to point to the registry
Create a new file called kubeadm-config.yml with the following contents somewhere. In this guide, we are creating it just in the home directory.
```
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
dns:
  imageRepository: sres.web.boeing.com:5000/coredns
imageRepository: sres.web.boeing.com:5000
networking:
  podSubnet: 172.16.0.0/16
  serviceSubnet: 10.96.0.0/12
```

Note: Using pod subnet 172.16.0.0 instead of the default 192.168.0.0 so it doesn't conflict with LCS's internal network. It probably didn't before, but just to be safe!

## An important NOTE before starting up the cluster, or joining other clusters
An edit to /etc/resolv.conf may be important at this step of the way. When CoreDNS spins up, it checks the resolv.conf file for domain search paths and nameservers. In the background though, it has a limitation of 6 search paths and 3 nameservers. However, 3 search paths are auto appended by CoreDNS itself. So in reality, your resolv.conf can only really have 3 search paths and 3 nameservers. If you have more, it won't break the cluster, but you'll get nagging warnings from every single pod you launch and will also crowd up /var/log/messages with these warnings. The best approach is to edit /etc/resolv.conf and remove any additional entries you may not need or redundant systems for nameservers. For more information, see the "Additional Notes" section at the bottom of this guide.

## Step 18: Create cluster
```
sudo kubeadm init --config=./kubeadm-config.yml
```

## Step 19: Get kubectl to work for current user
```
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

## Step 20: Verify that the control-plane started and label your node
```
kubectl get nodes -o wide
```
you should see the following:
```
NAME                       STATUS   ROLES                  AGE   VERSION          INTERNAL-IP     EXTERNAL-IP   OS-IMAGE                  KERNEL-VERSION                    CONTAINER-RUNTIME
krakenetes.cs.boeing.com   Ready    control-plane,master   33m   v1.21.14+2.el8   10.129.75.134   <none>        Oracle Linux Server 8.3   5.4.17-2136.313.6.el8uek.x86_64   cri-o://1.21.7
```
Notice that the external IP is not set. A network add-on must be added

Also, to make node affinity work in all of these templates, set a label on your node
```
kubectl label node <YOUR NODE NAME> node=<NODE NAME OF YOUR CHOOSING>
```
This step is optional if you will not have worker nodes. But if you do, this makes it a LOT easier to control where pods get scheduled. Otherwise the default scheduler will just throw pods across your entire cluster to wherever it feels like it.

## Step 21: Remove the taints from the master node so that it can be used as a worker node
```
kubectl taint nodes --all node-role.kubernetes.io/master-
```

## Step 22: Configure network add-on (Calico CNI with VXLAN)
Using calico in this example

Two files are required: tigera-opeartor.yaml and custom-resources.yaml

The two files are included with the installation instructions. If using those,
you can skip ahead to Step 21.1

If not, continue here:

Files sourced from:
https://docs.projectcalico.org/manifests/tigera-operator.yaml
https://docs.projectcalico.org/manifests/custom-resources.yaml

As of writing this document, the version of the operator image is v1.29.3

Both files need to be modified to use a copied image from gitlab
### For tigera-operator.yaml
If using the provided tigera-operator.yaml, there is a definition for an imagePullSecret at the top of the file.
Replace \<YOUR_BASE64_ENCODED_DOCKER_CONFIG_FILE> with the contents of the config_base64 file you created in Step 13 (for sres).

If not using it, add the sres image pull secret after the namespace creation at the top:
```
---
# Image pull secret for sres
---
apiVersion: v1
data:
  .dockerconfigjson: <YOUR_BASE64_ENCODED_DOCKER_CONFIG_FILE>
kind: Secret
metadata:
  name: sres-imagepullsecret
  namespace: tigera-operator
type: kubernetes.io/dockerconfigjson
---
```

Then find where the image is defined as:
```
          image: quay.io/tigera/operator:v1.29.3
```
And change it to:
```
          image: sres.web.boeing.com:5000/tigera/operator:v1.29.3
```

Also find the service account and add the imagePullSecrets:
```
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tigera-operator
  namespace: tigera-operator
imagePullSecrets: # Add this
  - name: sres-imagepullsecret
```

### For custom-resources.yaml
If not using the provided custom-resources.yaml,
Then add the following under spec for the 'kind: Installation' section of the yaml
```
  variant: Calico
  registry: sres.web.boeing.com:5000
  imagePullSecrets:
    - name: sres-imagepullsecret
```

Under calicoNetwork:
```
bgp: Disabled
nodeAddressAutodetectionV4:
      kubernetes: NodeInternalIP
```

Under ipPools change VXLANCrossSubnet to use VXLAN all the time:
```
encapsulation: VXLAN
natOutgoing: Enabled
```

Copy these two files to the server.

Note: Using vxlan all the time allows for nodes on the same subnet (such as two vms on azure) be able to communicate without any custom user defined routing having to be defined. Otherwise pod-to-pod communication will NOT WORK on the same subnets. Only cross subnet. This fixes that. Also, settting nodeAddressAutodetectionV4 to NodeInternalIP sets the calico-node pods on the worker nodes to use the node's public IP address as the adapter to go to the network instead of pointing a finger at the first adapter it finds and choosing that (first-find is default). This was a problem on nodes that, for example, have two networks (like in LCS).

### Step 22.1: Start calico
```
kubectl create -f tigera-operator.yaml
kubectl create -f custom-resources.yaml
```

### Step 22.2: Check calico system is running
```
kubectl get pods -n tigera-operator
kubectl get pods -n calico-system
kubectl get pods -n calico-apiserver
```
All pods should be in running state

## Step 23: Create a certificate for the box through the boeing certificates portal. Grab the crt and key file.
You have to do the certificates training to be able to create these. Otherwise you'll get an access denied on the following link.
Go to https://certificates.web.boeing.com/aperture/certificates

* Click "Create a New Certificate" in the top right corner
* Choose "Policy/Boeing BAS TLS/Manual/bte-kraken" from the dropdown
* Give it a nickname that is the URL of the server
* Description: whatever

Click Next

* Generate a CSR for me
* Common Name: URL of the server
* City/Locality: Seattle
* State/Province: WA
* Domain: \<empty>

Click Next
* Subject Alternative Names (DNS): \<empty>
* Approvers: \<empty>

Click Next
* Certificate X has been submitted

Template you'll get is: Boeing BAS CMI Enhanced SSL Server G2
Your certificate should now show up in the list of certificates

Click Download on the right side
* Format: PEM (PKCS #8)
  * Also include: Root Chain, Private Key
* Chain Order: End Entity First
* Password: follow the rules, don't forget the password, you'll need it to decrypt (NextGeneration1!)
* Extract PEM Contents into separate files UNchecked.

This will download a .pem file that contains all the chaining certs and the private key
Open up the pem file and move the encrypted private key from the end into a new file called .key
Copy the two files to the server.

Once on the server, you need to decrypt the private key
```
openssl rsa -in <private key filename> -out <decrypted private key file name>
```

## Step 24: Install ingress nginx (v1.7.0 is the last version that supports k8s v1.25)
Note - please check the compatibility of your version against the compatibility chart on the [ingress-nginx](https://github.com/kubernetes/ingress-nginx) readme!

Copy the ingress_nginx_namespace_template.yml and nginx_v170_template.yml to the destination box

First, apply the ingress_nginx_namespace_template.yml to create the namespace.
```
kubectl apply -f ingress_nginx_namespace_template.yml
```
We're doing this separately so we can add the certificates we created in the previous step as it is done via command line and not template.

Then, add the certificates:
```
kubectl create secret tls ca-certificate --key < private key filename > --cert < certificate filename > -n ingress-nginx
```

A modification is required to the all-in-one nginx_v170_template.yml. Since we are not running on a cloud provider to
provide an external load balancer, the external IP cannot be set automatically on the service for nginx. In the yaml file,
find the service with the section externalIPs where \<IP ADDRESS OF BOX GOES HERE> is. Ping your box's DNS address and grab
that IP address. Replace \<IP ADDRESS OF BOX GOES HERE> with the IP address of the box. Also, set the node affinity to the label you set on your master node.

Once that is done, apply the all-in-one nginx_v170_template.yml
```
kubectl apply -f nginx_v170_template.yml
```

This should create all of the service accounts, roles, clusterroles, services, deployments, jobs, etc. that are necessary to spin up nginx.

You can verify things are running properly with
```
kubectl get pods -n ingress-nginx
```
Verify that the ingress-nginx-controller is ready 1/1

The other two admission create and patch pods will not be running, but completed. These were just jobs.

Verify that the ingress controller loadbalancer service has been assigned an external IP:
```
kubectl get services -n ingress-nginx
```
You should see ingress-nginx-controller as a loadbalancer with an external IP that you provided in the service config.

If you see that all the pods in the ingress-nginx namespace are pending, and you inspect them. You might find that they won't start due to a taint on the node. Run the following command to remove all taints on the node:
```
kubectl patch node <YOU BOX NAME HERE> -p '{\"spec\":{\"taints\":[]}}'
```
### Installing a controller on a worker node instance
The controller we just installed runs on a master node. If you have worker nodes, you may want to be able to access your worker nodes directly instead of passing all traffic through the master node.
The reason for this is to reduce the number of network hops to reach your worker node's services, which can get slow if your nodes are far apart.
The solution to this is to create an ingress controller on each node, that is listening only for ingresses tagged to that node's ingress class.
This will allow you to create ingresses that only get picked up by the controller on that specific node, and exposes your services on that node's address (or IP if it doesn't have a DNS address).

For each worker node, we will need to add the corresponding certificate for the box as a secret into the ingress-nginx namespace. We have already created one for the master node called ca-certificate. The command is the same, but change the name to your node name:
```
kubectl create secret tls ca-certificate-< NODE NAME > --key < private key filename > --cert < certificate filename > -n ingress-nginx
```

There is a template in the nginx_deployment folder called controller-node-instance-deploy.yml, which contains a service that is specifically exposing the nginx controller on the destination node's IP address, and contains the deployment of a new controller that listens on an ingress class named "nginx-\<NODE\>". Make sure you replace all of the instances of \<NODE\> in the template with the label of the node you're deploying to and replace \<IP ADDRESS OF BOX GOES HERE\> with the IP address of the node.

Once deployed, this will spin up a controller on the targeted node that will pick up any ingresses destined for the ingress class "nginx-\<NODE\>". You will then able to go to \<IP ADDRESS OF NODE\>/youringresspath to access your services

### Exposing TCP or UDP services
By default, the ingress controller is only responsible for HTTP/S traffic on ports 80 and 443. Services that are HTTP work fine with this and an ingress is all they need. Service that require TCP or UDP connections though to a specific port require special configuration and mappings through nginx. For example, if you want to expose a redis service at TCP port 6379, you'll have to do the following three things.

1. You must create a tcp-services configmap that maps an incoming port to the service (see tcp-services-configmap-example.yml):
```
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: tcp-services
      namespace: ingress-nginx
    data:
      9000: "namespace/redis-service:6379"
```
This example here maps port 9000 to redis-service:6379 where redis-service is the name of the actual service created for the redis app/pod.

2. You must then edit the service on your target node to expose port 9000 (do not add a nodePort - it gets generated):
```
    spec:
      ports:
        - name: http
          protocol: TCP
          appProtocol: http
          port: 80
          targetPort: http
          nodePort: 30169
        - name: https
          protocol: TCP
          appProtocol: https
          port: 443
          targetPort: https
          nodePort: 31032
        - name: redis # Add this
          protocol: TCP
          port: 9000
          targetPort: 9000
```
The service will be located in the ingress-nginx namespace under Services with the name "ingress-nginx-controller" or "ingress-nginx-controller-\<NODE\>" if this is on a worker node.

3. (Do once only) Edit the deployment for the controller to tell it where the tcp-services configmap is located:
To do this, find the deployment for the controller of interest. Either called "ingress-nginx-controller" or "ingress-nginx-controller-\<NODE\>".
Edit this file and find the args provided to the controller. Then along with all the other args, add:
```
    args:
        - /nginx-ingress-controller
        - .... other args ....
        - --tcp-services-configmap=ingress-nginx/tcp-services
```
This edit will restart the controller, and it will now look at your configmap to pull TCP services to expose. If editing the deployment, follow the same structure of the arguments. If they are in single quotes, make sure you add the new one in single quotes. If you're editing the deployment yaml, you don't need single quotes.

Once you've done the above, you will now be able to access redis at \<YOUR BOX IP OR ADDRESS\>:9000

For configuring UDP ports, the steps above are basically the same, but replace tcp with udp everywhere.

## Step 25: Deploy the dashboard
If you're using the provided dashboard_template.yml file, the gitlab registry secret needs to be edited.
At the top of the file, find the \<YOUR_BASE64_ENCODED_DOCKER_CONFIG_FILE> keyword and replace it with the
contents of the config_base64 file you created in Step 13. Then you can skip to the deployment directly.

If you're not using the provieded dashboard_template.yml file, then grab the copy from the following URL:

https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

and save it as dashboard_template.yml

Then make the following modifications:
1. At the top of the file, add the following:
```
---
# Image pull secret for sres
---
apiVersion: v1
data:
  .dockerconfigjson: <YOUR_BASE64_ENCODED_DOCKER_CONFIG_FILE>
kind: Secret
metadata:
  name: sres-imagepullsecret
  namespace: kubernetes-dashboard
type: kubernetes.io/dockerconfigjson
```
2. At the kind: Service definition, change:
   1. The port to 9090 (“port” refers to the container port exposed by a pod or deployment)
   2. The targetPort to 9090 (“targetPort” refers to the port on the host machine that traffic is directed by the ingress)
3. Change the two images being pulled with /kubernetesui/dashboard:tag and /kubernetesui/metrics-scraper:tag to have sres.web.boeing.com:5000 before them (keeping the kubernetesui)
4. Add the imagePullSecrets definition under the second spec (before securityContext) for each deployment:
```
imagePullSecrets:
  - name: sres-imagepullsecret
```
5. For the dashboard deployment template, change:
   1. The containerPort to 9090
   2. Under args:
      1. Remove "- --auto-generate-certificates"
      2. Add "- --insecure-port=9090"
   3. The livenessProbe scheme to HTTP and port to 9090
6. (Optional - If setting up keycloak, we will be replacing this ingress with auth later) Add the ingress for the dashboard at the bottom of the file:
```
---
# Ingress for dashboard
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: dashboard-ingress
  namespace: kubernetes-dashboard
  annotations:
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/rewrite-target: /$2
    nginx.ingress.kubernetes.io/configuration-snippet: |
      rewrite ^(/dashboard)$ $1/ redirect;
    kubernetes.io/ingress.class: "nginx"
spec:
  rules:
  - http:
      paths:
      - path: /dashboard(/|$)(.*)
        pathType: Prefix
        backend:
          service:
            name: kubernetes-dashboard
            port:
              number: 9090
```

### Deploy the dashboard
```
kubectl apply -f dashboard_template.yaml
```

## Step 26 (Optional): Deploy Keycloak

### Create the necessary certificates keystore
1. Create a folder called certs in /home/kraken (assuming kraken user).
2. Move the server .pem certificate from Step 22 into this folder.
   1. Move the file, rename it to .crt
3. cd into the folder
4. Run:
```
curl http://www.boeing.com/crl/Boeing%20Basic%20Assurance%20Software%20Root%20CA%20G2.crt | openssl x509 -inform DER -out ./boeing-g2.crt
curl http://www.boeing.com/crl/Boeing%20Basic%20Assurance%20Software%20Issuing%20CA%20G3.crt | openssl x509 -inform DER -out ./boeing-g3.crt
echo -n | openssl s_client -connect apps.system.tas-ewd.cloud.boeing.com:443 | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > ./sso-tile.crt
```
5. make a /data/keycloak folder then run
6. Generate a java cert truststore in your home directory ~/ by importing the three different certs
   1.  keytool -import -keystore clientkeystore -file certs/boeing-g2.crt -alias boeing-g2-cert
       1.  When prompted for password, enter a new password for the keystore (don't forget it)
   2.  keytool -import -keystore clientkeystore -file certs/boeing-g3.crt -alias boeing-g3-cert
   3.  keytool -import -keystore clientkeystore -file certs/squidward.cs.boeing.com.crt -alias squidward.cs.boeing.com
   4.  keytool -import -keystore clientkeystore -file certs/sso-tile.crt -alias sso-tile-cert
7. Move the keystore to /data/keycloak
   1. sudo mv clientkeystore /data/keycloak
8. Change folder ownership
   1. sudo chown -R admin:root /data/keycloak

### Deploy keycloak
We will use the included keycloak_template.yml to deploy, but first we need to populate some fields
Edit the following in the template:
1. \<YOUR BOX HOSTNAME> should be replaced with the DNS hostname of the box
2. \<YOUR BOX CERT> should be replaced with the name of the certificate for the box that you put in the /home/kraken/certs folder
3. \<KEYSTORE PASSWORD> should be replaced with the password you created for the keystore in the previous step
4. \<ADMIN USER> should be replaced with the username you'll be using to log in to the admin UI
5. \<ADMIN PASSWORD> plain text password for the admin user. This can be changed in the UI later.
6. \<YOUR_BASE64_ENCODED_DOCKER_CONFIG_FILE> should be replaced with the contents of the config_base64 file you created in Step 13.

### Create the kraken realm through the web interface and admin user
1. Go to https://squidward.cs.boeing.com/keycloak/admin/
   1. Log in with \<ADMIN USER> and \<ADMIN PASSWORD>
2. In the top left you'll see a realms dropdown
   1. Click create realm
   2. Realm name: kraken

Once the realm is created:
1. Select the realm in the top left
2. Click Users in the left pane
3. Username: kraken-admin
4. Click Create
Once the user is created, it'll go onto the users information page
1. Click Credentials
2. Click Set Password
   1. \<set admin password for kraken user - this does not have to be the same as the KEYCLOAK_ADMIN_PASSWORD>
   2. Uncheck temporary
3. Go to Role mapping
   1. Click Assign Role
   2. Drop down the Filter and select Filter by clients
   3. search for realm-management
   4. change the number of items displayed to 20 per page
   5. check the select all checkbox at the table header
   6. Click Assign
   7. Click Assign Role again
   8. Drop down the Filter and select Filter by clients
   9. search for account
   10. select manage-account and all of the view-* options
   11. Click Assign
4.  Go to Realm settings in the left pane
    1.  Go to Login tab at the top
    2.  Under Email settings:
        1.  Email as username: On
        2.  Login with email: On

### Set up SSO tile on PCF for keycloak
\<TODO>

After setting up the wsso-tile, click on manage on the service.

This will take you to a page that shows registered apps.

1. Click register app in the top right.
2. App Name: <your box name>-keycloak
3. App Type: Web App
4. Select Identitiy Providers: PingFederation
5. Redirect URI Whitelist: https://\<YOUR BOX URL>/keycloak/realms/kraken/*,https://\<YOUR BOX URL>
6. Authorization for user:
   1. Leave all unchecked, except for System Permissions, check openid and profile
7. Click REGISTER APP

This will now pop up app credentials. SAVE THESE AND DO NOT LOSE THEM.

You will be setting SSO_CLIENT_ID to provided App ID

You will be setting SSO_CLIENT_SECRET to provided App Secret

### Run the scripts required to set up wsso
There are 2 scripts that set up the LDAP identity provider and the WSSO user federation
1. identityProvider.ts
2. userFederationSetup.ts

These need to be run on a machine with node installed.

Pull down the project with the scripts: [keycloak-setup](https://git.web.boeing.com/song/kraken/keycloak-setup)

Run:
```
$ npm install
```
set a few environment variables prior to running the script:
```
export KEYCLOAK_BASE_URL=<YOUR BOX BASE URL>/keycloak
export KEYCLOAK_USERNAME=kraken-admin
export KEYCLOAK_PASSWORD=<PASSWORD YOU SET FOR kraken-admin>
export BIND_CREDENTIALS=<CREDENTIALS FOR LDAP>
export SSO_CLIENT_ID=<GIVEN BY THE SSO TILE YOU CREATED IN THE PREVIOUS STEP>
export SSO_CLIENT_SECRET=<GIVEN BY THE SSO TILE YOU CREATED IN THE PREVIOUS STEP>
```
Then run the two scripts
```
ts-node identityProvider.ts
ts-node userFederationSetup.ts
```

## Step 27 (Optional): Set up oauth2-proxy for dashboard wsso

### Create namespace and create ca cert configmap
First we will create the namespace for oauth2-proxy
```
kubectl apply -f oauth2-proxy_namespace.yml
```
Then we will create a configmap based on our certificate chain
```
kubectl -n oauth2-proxy create configmap ca-store --from-file=/home/kraken/certs/<YOUR BOX CERT FILE NAME>.crt
```

### Create client for oauth2-proxy in keycloak
1. Go to https://squidward.cs.boeing.com/keycloak/admin/
   1. Log in with \<ADMIN USER> and \<ADMIN PASSWORD>
2. Select the kraken realm
3. Go to Clients
   1. Click Create client
   2. Client Type: OpenID Connect
   3. Client ID: oauth2-proxy
   4. Name: oauth2-proxy
   5. Description: Authenticating client for access to applications via oauth2-proxy. Also used as authenticating client for kube-apiserver API.
   6. Click Next
   7. Client authentication: On
   8. Authorization: Off
   9. Authentication Flow:
      1.  Standard Flow checked
      2.  Everything else unchecked
  10. Click Save

After saved, it'll redirect to more configuration options
1. Scroll down to "Valid redirect URIs" and add:
   1. https://\<YOUR BOX URL>/oauth2-proxy/callback
2. Confirm that Client authentication is turned on. If off, turn back on.
3. Save
4. Now scroll to the top and go to the Client Scopes tab
   1. In client scopes, click oauth2-proxy-dedicated (should be only blue link)
   2. Now click Add mapper and select By Configuration
   3. Select Audience
   4. Name it "Audience for oauth2-proxy
   5. Included Client Audience: select oauth2-proxy
   6. Leave the rest default
   7. Click Save
   8. Click back to Client details in the top path

We also need to make a group mapper
1. Go to Client Scopes on the left and create a new client scope
   1. Name: groups
   2. Description: OpenID Connect scope for groups
   3. Type: Optional
   4. Display on consent screen: Off
   5. Include in token scope: On
   6. Click save
2. Now go to the mappers tab at the top
   1. Click Configure a new mapper
   2. Select group membership
   3. Name: groups
   4. Token Claim Name: groups
   5. Full group path: Off
   6. Add to ID Token: On
   7. Add to access token: On
   8. Add to userinfo: On
   9. Click Save
3. Go To clients now and select oauth2-proxy that we created earlier
    1. Go to the Client scopes tab
    2. Click Add client scope
    3. Select the new scope you just created called groups
    4. Add as default
4. Now go to the Credentials tab of oauth2-proxy client
   1. Copy the Client Secret and hang on to it

### Deploy oauth2-proxy
Using the oauth2-proxy_template.yml, we will deploy the service

Before deploying, there are a few variables that must be replaced in the template:
1. \<YOUR_BASE64_ENCODED_DOCKER_CONFIG_FILE> should be replaced with the contents of the config_base64 file you created in Step 13.
2. \<CLIENT SECRET> is to be replaced with the client secret you just copied
3. \<REDIRECT URL> is to be replaced with the "Valid redirect URIs" you just set above
4. \<OIDC ISSUER URL> is to be replaced with https://\<YOUR BOX URL>/keycloak/realms/kraken
5. \<MOUNT PATH> is to be replaced with /etc/ssl/certs/\<YOUR BOX CERT FILE NAME>.crt
6. \<SUB PATH> is to be replaced with \<YOUR BOX CERT FILE NAME>.crt
7. \<TLS HOST> is to be replaced with \<YOUR BOX URL>

### Modify dashboard ingress with new authentication redirect
Create a new dashboard_ingress.yml file with:
```
---
# Ingress for dashboard
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: dashboard-ingress
  namespace: kubernetes-dashboard
  annotations:
    nginx.ingress.kubernetes.io/auth-response-headers: "Authorization"
    nginx.ingress.kubernetes.io/auth-url: "https://$host/oauth2-proxy/auth"
    nginx.ingress.kubernetes.io/auth-signin: "https://$host/oauth2-proxy/start?rd=$escaped_request_uri"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/rewrite-target: /$2
    nginx.ingress.kubernetes.io/configuration-snippet: |
      rewrite ^(/dashboard)$ $1/ redirect;

      auth_request_set $name_upstream_1 $upstream_cookie_name_1;
      access_by_lua_block {
        if ngx.var.name_upstream_1 ~= "" then
          ngx.header["Set-Cookie"] = "name_1=" .. ngx.var.name_upstream_1 .. ngx.var.auth_cookie:match("(; .*)")
        end
      }
    kubernetes.io/ingress.class: "nginx"
spec:
  rules:
  - http:
      paths:
      - path: /dashboard(/|$)(.*)
        pathType: Prefix
        backend:
          service:
            name: kubernetes-dashboard
            port:
              number: 9090
```

### Create cluster role binding to map a custom group of users to a role
We will create a cluster role to map cluster roles to OIDC groups. In this example, we are mapping a group called kubernetes-admins to one of the default cluster-admin roles. It is important that this be created in the default namespace. The oidc_group: prefix is a custom prefix we will tell the api server to use in the next step.

Create a new file called oidc_clusterrole.yml with the contents:
```
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  namespace: default
  name: kubernetes-admins
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
subjects:
  - kind: Group
    name: oidc_group:kubernetes-admins
    apiGroup: rbac.authorization.k8s.io
```

```
kubectl apply -f oidc_clusterrole.yml
```

Note: A cluster role binding can also be created per user. In that case, under subjects,
you would have the following:
```
subjects:
  - kind: User
    name: oidc_user:<email of user>
    apiGroup: rbac.authorization.k8s.io
```

### Configure kube-apiserver to use oidc bearer tokens
First, we need to move our certificate file for our box to the certs folder
that kubernetes accesses. This is located at:
```
/etc/kubernetes/pki
```
Copy \<YOUR BOX CERT FILE NAME>.crt into this directory

We will now edit the startup script used by kubernetes for kube-apiserver.
The template is located on the host machine at
```
/etc/kubernetes/manifests/kube-apiserver.yaml
```
Open up the file and find the command under spec: containers: command:
The command will be quite long and we will be appending to the end.
At the end of the command, add:
```
    - --oidc-issuer-url=https://<YOUR BOX URL>.cs.boeing.com/keycloak/realms/kraken
    - --oidc-ca-file=/etc/kubernetes/pki/<YOUR BOX CERT FILE NAME>.crt
    - --oidc-client-id=oauth2-proxy
    - --oidc-username-claim=email
    - "--oidc-username-prefix=oidc_user:"
    - --oidc-groups-claim=groups
    - "--oidc-groups-prefix=oidc_group:"
```
Make sure that the oidc-username-prefix and oidc-groups-prefix is in quotes like in the
example above. If you do not quote it, it'll syntax error on the ending colon. If you
only quote the end of the command, it'll append the quotes into the prefix and it will
not correctly match to the name in the ClusterRoleBinding. This is also defining a
custom prefix for user authentication using the oidc_user: prefix. The prefixes could be
the same (just oidc: for example). The only thing that matters is that the ClusterRoleBinding
name matches the prefix.

Once you save the file, kubelet will automatically restart the kube-apiserver. It will take
a moment, and during that time, kubectl will not work.

### Configuring a user to access the dashboard as an administrator
In previous steps, we created a mapping for a group named "kubernetes-admins" to have cluster-admin. However, we have not created or added any users to this group. We can pre-populate groups in keycloak from the LDAP AD group we have added. All of those users are synced to keycloak ahead of time.

To add users to a keycloak group:
1. Go to https://squidward.cs.boeing.com/keycloak/admin/
   1. Log in with \<ADMIN USER> and \<ADMIN PASSWORD>
2. Select the kraken realm
3. Go to Groups
   1. Click the kubernetes-admins group
   2. Go to Members tab
   3. Click Add member
   4. Search members from AD group to add, check off each, and click add.

### A side note on keycloak mappings
Mappings are essentially definitions on how to read incoming tokens/objects or what to put in outgoing tokens. For wsso as an identifiy provider, we define bemsid as an incoming piece of data through a mapping and we also map the email claim from the token to the username. For LDAP User Federation, we define what ldap name to assign to what user attribute. Then for a client, the mappings define what to include inside of the token passed to the clients.

As an example, here is what a WSSO token contains:
```
"data": {
  "nonce": "Unique value associating request to token",
  "sub": "Subject (whom the token refers to)",
  "scope": [
    "openid",
    "profile"
  ],
  "client_id": "ID of the application bound to WSSO tile",
  "cid": "Copy of client_id",
  "azp": "Authorized Party (the party to which this token was issued)",
  "grant_type": "authorization_code",
  "user_id": "Unique ID of the actual user (used for linking users in Keycloak to their actual user entry)",
  "origin": "pingfederation",
  "user_name": "User's BEMS",
  "email": "User's email",
  "auth_time": "Time when authentication occurred",
  "rev_sig": "",
  "iat": "Issued at (epoch time)",
  "exp": "Expiration time (epoch time),
  "iss": "Issuer (who created and signed this token)",
  "zid": "da9ff448-fd21-41b6-a5c1-491e910ff37a",
  "aud": [ "The audience of the token"
    "openid",
    "<client_id goes here>"
  ]
}
```

## How to join worker nodes to master node
Once you have gone through the above steps to create a master node, joining a worker node on another box is simple.

The other box must have all of the prerequisite rpms installed and kubadm working. Once that is all set up, run the following command on the master node to generate the join command:
```
$ kubeadm token create --print-join-command
```

This will generate a join command that you can now run on the worker box to create a node. An example of the command will look like:

```
sudo kubeadm join 10.128.0.37:6443 --token j4eice.33vgvgyf5cxw4u8i \
    --discovery-token-ca-cert-hash sha256:37f94469b58bcc8f26a4aa44441fb17196a585b37288f85e22475b00c36f1c61
```

Run this command on the worker node. You will get an output that says "This node has joined the cluster".

Afterwards, you should be able to see this node in the master cluster by running
```
$ kubectl get nodes
```
on the master node. The new node will have a hostname label like so:
```
kubernetes.io/hostname: <URL OF WORKER NODE BOX>
```

This hostname label can now be used in a deployment to direct pods to run on the worker. Alternatively creating a custom label for the node is a better way to direct everything there. To do that, run:
```
$ kubectl label node <WORKER NODE NAME> node=<LABEL>
```

Now, if a namespace is tagged with that label, every pod in that namespace will go to that worker node. An example of a namespace config doing that:
```
apiVersion: v1
kind: Namespace
metadata:
  name: <NAMESPACE NAME>
  annotations:
   scheduler.alpha.kubernetes.io/node-selector: node=<LABEL>
  labels:
    name: <NAMESPACE NAME>
```

## Additional notes
You may notice that in your cluster, every pod you launch has a warning event for DNSConfigForming with the message:
```
Search Line limits were exceeded, some search paths have been omitted, the applied search line is: <paths and stuff here>
```
If you count how many paths it's showing, you'll notice it's 6 of them...

CoreDNS automatically appends 3 search domains to the search path. Specifically the following 3:
```
kubernetes-vlift.svc.cluster.local
svc.cluster.local
cluster.local
```
These additional search paths allow you to access services within the cluster network by using addresses like:
```
<K8S SERVICE>.<NAMESPACE>.svc.cluster.local:<K8S SERVICE PORT>
```
The unfortunate part about this is that kubelet and coredns can only handle 6 search paths.. because it's a magic number? I don't know. Host level existing search paths are defined by the /etc/resolv.conf search entry and the only way to "fix" this and make the warning go away is to limit the number of search paths in your /etc/resolv.conf file to 3. That way when coredns appends the three additional ones, it won't exceed 6. On some machines, you can do this without messing up name resolution. On LCS machines for example, there are 9 populated by default for the LCS network. We have managed to reduce it to three without messing up name resolution, however.

On top of that, there is a bit of an impact. Kubelet will CONTINUOUSLY log this error. It'll show up in your pod events log, and it'll show up in /var/log/messages excessively. There is no way to turn this off other than limiting your /etc/resolv.conf search path entires.

Another warning you may notice from DNSConfigForming is nameserver limits exceeded. This warning will most likely only show up on the CoreDNS pod itself. You'll see something like:
```
Nameserver limits were exceeded, some nameservers have been omitted, the applied nameserver line is: <nameservers and stuff here>
```
Now, if you count how many IPs it's showing, you'll notice it's 3 of them...

Similar limitation here. CoreDNS can only handle 3 nameservers! Why? Dunno. Anyway again the only way to fix this is to limit the number of nameservers in your resolv.conf file.

So the key takeaway is try to limit your resolv.conf search paths and nameservers to 3 for both.

If you have modified your resolv.conf after your node was already up, you need to do two things for it to take effect.
1. Restart kubelet on the affected node:
```
sudo systemctl restart kubelet
```
2. Restart CoreDNS
On the machine you run kubectl (talking to master node), run:
```
kubectl -n kube-system rollout restart deployment coredns
```

More information here: https://support.d2iq.com/hc/en-us/articles/12928841075476-DNS-warning-Search-Line-limits-were-exceeded-some-search-paths-have-been-omitted
And here: https://my.f5.com/manage/s/article/K18352919#:~:text=Kubernetes%20allows%20for%20a%20maximum,in%20the%20%2Fetc%2Fresolv.


## Maintenance

Somestimes pods will get stuck in an unknown state or a failed state and they need to be manually cleaned up. To do so, run the following commands:

```
# To delete all pods in all namespaces:
export CONTAINERSTATUS=<container status>
kubectl get pods --all-namespaces | grep $CONTAINERSTATUS | awk '{print $2 " --namespace=" $1}' | xargs kubectl delete pod

# To delete all pods in a specific namespace:
export NAMESPACE=<namespace>
export CONTAINERSTATUS=<container status>
kubectl --namespace=$NAMESPACE get pods -a | grep CONTAINERSTATUS | awk '{print $1}' | xargs kubectl --namespace=$NAMESPACE delete pod -o name

```

Where CONTAINERSTATUS is usually one of "Evicted", "Error", or "ContainerStatusUnknown"

## Kubernetes dashboard upgrade guide
Refer to the top of the dashboard_v7_template.yml file to see what steps are required
to upgrade versions.
