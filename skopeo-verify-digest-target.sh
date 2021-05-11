#!/bin/bash
# registry,image_name,tag,digest,mtype,os,arch,variant,insecure,digest_source,image_type
#quay.io,opencloudio/ibm-auditlogging-operator,3.7.1,sha256:14a06923d21e20f5831878cc2f450b21d143afd88eb0fb7eb2bae7194ab62901,LIST,"","","",0,CASE,""

# skopeo copy --src-cert-dir /root/.airgap/certs --debug docker://mut-repos-mirror-01.infra.asten:5000/cp/cp4mcm/admission-controller:2.1.6-ibm-management-image-security-enforcement-ppc64le dir:/var/lib/repo/cp4mcm/2.1.6/offline/cp4mcm-registry
Parallel=5
Count=1
#
Arg=$1
[ "$Arg" != "refresh" ]&["$Arg" != "" ] && printf $0" refresh : to update images on disk if Digest sha256 is different \n"$0" : verify only and list\n" && exit

for File in $(ls ./*images.csv)
do
	#echo $File
	awk -F "," '{print $2":"$3}' $File
done|grep -Ev "image_name:tag|-s390x" |tee image-verif.lst

echo "Enter to continue, or ctrl-C"
read
for Image_tag in $(cat image-verif.lst)
do
	Dir=$(echo $Image_tag| tr ":" "-"| tr "/" "_")
	mkdir -p ./cp4mcm-registry/$Dir
	#skopeo copy --src-cert-dir /root/.airgap/certs docker://mut-repos-mirror-01.infra.asten:5000/$Image_tag dir:/var/lib/repo/cp4mcm/2.1.6/offline/cp4mcm-registry/$Dir

	FullDir=$(pwd $Dir)"/cp4mcm-registry/$Dir"
	#Skopeo_Source=$(skopeo inspect --creds $EXTERNAL_DOCKER_USER:$EXTERNAL_DOCKER_PASSWORD docker://localrepos.infra.asten:5000/$Image_tag |jq .Digest)
	Skopeo_Target=$(skopeo inspect --creds $LOCAL_DOCKER_USER:$LOCAL_DOCKER_PASSWORD docker://ocregistry.infra.asten:5000/$Image_tag |jq .Digest)
	##echo "skopeo inspect --creds $EXTERNAL_DOCKER_USER:$EXTERNAL_DOCKER_PASSWORD dir:$FullDir |jq .Digest"
	Skopeo_Source=$(skopeo inspect --creds $LOCAL_DOCKER_USER:$LOCAL_DOCKER_PASSWORD dir:$FullDir |jq .Digest)
	Skopeo_csv=$(awk -F ","  '/'$(echo $Skopeo_Targeti)'/ {print $4}' *images.csv|tail -1)
	if [ "$Skopeo_csv" != "$Skopeo_Source" ]
	then
		echo $Image_tag" $Skopeo_Source != $Skopeo_csv"
		echo "Registry: "$Skopeo_Target
		if [ "$Arg" == "refresh" ]
		then
			skopeo copy --all --dest-creds $LOCAL_DOCKER_USER:$LOCAL_DOCKER_PASSWORD  dir:/var/lib/tempo/cp4mcm/2.1.6/offline/cp4mcm-registry/$Dir docker://ocregistry.infra.asten:5000/$Image_tag && \
			skopeo inspect --creds $LOCAL_DOCKER_USER:$LOCAL_DOCKER_PASSWORD dir:$FullDir |jq .Digest &
			Count=$((Count+1))

		else
			echo skopeo copy --all --dest-creds $LOCAL_DOCKER_USER:\$LOCAL_DOCKER_PASSWORD  docker://ocregistry.infra.asten:5000/$Image_tag dir:/var/lib/tempo/cp4mcm/2.1.6/offline/cp4mcm-registry/$Dir
		fi
	else
		echo $Dir
	
	fi
	if [ $Count -eq $Parallel ]
	then
		wait
		Count=1

	fi

done
