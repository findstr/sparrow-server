dir=$(dirname "$PWD")
echo $dir
mkdir -p "$dir/k8s/volume"
chmod 777 "$dir/k8s/volume"
minikube start	\
	--mount-string="$dir/:/mnt/local"	\
	--mount	\
	--image-mirror-country='cn' \

minikube image load registry.cn-shanghai.aliyuncs.com/findstr-mirror/ubuntu
minikube image load registry.cn-shanghai.aliyuncs.com/findstr-mirror/etcd:latest
minikube image load registry.cn-shanghai.aliyuncs.com/findstr-mirror/kvrocks:latest
minikube image ls
