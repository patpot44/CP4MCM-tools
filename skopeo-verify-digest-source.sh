#!/bin/bash
# 
# registry,image_name,tag,digest,mtype,os,arch,variant,insecure,digest_source,image_type
#quay.io,opencloudio/ibm-auditlogging-operator,3.7.1,sha256:14a06923d21e20f5831878cc2f450b21d143afd88eb0fb7eb2bae7194ab62901,LIST,"","","",0,CASE,""

# skopeo copy --src-cert-dir /root/.airgap/certs --debug docker://mut-repos-mirror-01.infra.asten:5000/cp/cp4mcm/admission-controller:2.1.6-ibm-management-image-security-enforcement-ppc64le dir:/var/lib/repo/cp4mcm/2.1.6/offline/cp4mcm-registry
Parallel=5
Count=1
Filelist=$0.lst
Arg1=
Arg2=
Arg3=
Refresh=False
Debug=False
Force=False
# not used for the moment to check if it is a good idea :
Registry_dir="./offline/cp4mcm-registry" 
External_registry=localrepos.infra.asten:5000
Local_registry=ocregistry.infra.asten:5000


# command and arguments 
for i in $@
do 
	case $i in
		"refresh") # Do the copy from registry to directory when Digest SH256 are different Registry is the source
		Refresh=True
		Arg1="refresh";;
		"-dotar") # Do one tar file in cp4mcm-registry for each image repository newly generated
		Arg3="dotar";;
		"--debug"|"-d") # More info displayed to debug
		Arg4="debug"
		Debug=True;;
		"--force"|"-f") # To force Copy with file $Filelist.digest-error
		Arg5="force"
		Force=True;;
		"help"|"-h"|"--help")
			echo $0" 				: list and verify only the Digest SHA256 between registry and directory. Source images information comes from *.csv files"
			echo $0" refresh 		: Do the copy from registry to directory when Digest SH256 are different Registry is the source."
			echo $0" <search value> : run the command by filtering with the value."
			echo $0" --force | -f 	: To force skopeo copy with file $Filelist.digest-error."
			echo $0" --dotar 		: Do one tar file in cp4mcm-registry for each image repository newly generated."
			echo $0" --debug | -d 	: More info displayed to debug."
		       	exit;;
		*) # All other options unknown are used 
			Filtre=$Filtre" "$i
			Arg2=$Filtre;;
	esac		
done
# check environnment
if [ -z $EXTERNAL_DOCKER_USER ]
then
	echo $0" : check the environment variable, perhaps use source ~/.registry to initialize."
	exit
fi

# to create the liste file
if [ -z $Filtre ] 
then
	for File in $(ls ./offline/*images.csv)
	do
		#echo $File
		awk -F "," '{print $2":"$3}' $File
	done |grep -Ev "image_name:tag|\-s390x|\-amd64|\-ppc64le"|tee $Filelist
else
	Filtre=$(echo $Filtre|sed 's/ /|/g')
	for File in $(ls ./offline/*images.csv)
  do
    #echo $File
    awk -F "," '{print $2":"$3}' $File
  done |grep -Ev "image_name:tag|\-s390x|\-amd64"|grep -E "$Filtre" |tee $Filelist
fi

echo "Enter to continue, or ctrl-C"
read

# to do the skopeo inspect of registry image and directory image
>$Filelist.copied
>$Filelist.digest-error
for Image_tag in $(cat $Filelist)
do
	Dir=$(echo $Image_tag| tr ":" "-"| tr "/" "_")
	[ ! -d ./offline/cp4mcm-registry/$Dir ] && mkdir -p ./offline/cp4mcm-registry/$Dir
	#skopeo copy --src-cert-dir /root/.airgap/certs docker://mut-repos-mirror-01.infra.asten:5000/$Image_tag dir:/var/lib/repo/cp4mcm/2.1.6/offline/cp4mcm-registry/$Dir

	FullDir=$(pwd $Dir)"/offline/cp4mcm-registry/$Dir"
	Skopeo_Source=$(skopeo inspect --creds $EXTERNAL_DOCKER_USER:$EXTERNAL_DOCKER_PASSWORD docker://localrepos.infra.asten:5000/$Image_tag |jq .Digest)
	Skopeo_Target=$(skopeo inspect --creds $EXTERNAL_DOCKER_USER:$EXTERNAL_DOCKER_PASSWORD dir:$FullDir |jq .Digest)
	if [ "$Skopeo_Source" != "$Skopeo_Target" ]
	then
		echo $Image_tag" $Skopeo_Source != $Skopeo_Target"
		if [ "$Arg1" == "refresh" ]
		then
			skopeo copy --all --src-creds $EXTERNAL_DOCKER_USER:$EXTERNAL_DOCKER_PASSWORD  docker://localrepos.infra.asten:5000/$Image_tag dir:/var/lib/repo/cp4mcm/2.1.6/offline/cp4mcm-registry/$Dir && \
			skopeo inspect --creds $EXTERNAL_DOCKER_USER:$EXTERNAL_DOCKER_PASSWORD dir:$FullDir |jq .Digest &
			echo $Dir>> $Filelist.copied
			Count=$((Count+1))

		else
			echo skopeo copy --all --src-creds $EXTERNAL_DOCKER_USER:\$EXTERNAL_DOCKER_PASSWORD  docker://localrepos.infra.asten:5000/$Image_tag dir:/var/lib/repo/cp4mcm/2.1.6/offline/cp4mcm-registry/$Dir
			echo $Image_tag>> $Filelist.digest-error 
		fi
	else
		if [ -z $Skopeo_Source ]&[ -z $Skopeo_Target ] 
		then 
			echo "ERROR : Digest SHA256 source and target null";echo $Image_tag>> $Filelist.digest-error
		else	
			printf $Dir" : Ok" && [ $Debug ] && printf " S: "$Skopeo_Source" T: "$Skopeo_Target"\n" || printf "\n"
		fi
	
	fi
	if [ $Count -eq $Parallel ]
	then
		wait
		Count=1

	fi

done

# to do the tar with the $Filelist.copied input
if [ "$Arg3" == "dotar" ]
then
	for f in $(cat $Filelist.copied)
    do
		cd offline/cp4mcm-registry
		tar -cvf $f.tar ./$f
		cd -
		echo "from ocregistry do:"
		echo "cd /var/lib/tempo/cp4mcm-registry"
		echo "wget --no-check-certificate https://localrepos.infra.asten/cp4mcm/2.1.6/offline/cp4mcm-registry/${f}.tar"
		echo "tar -xf ${f}.tar"
		echo "cd  /var/lib/tempo/ && bash skopeo-verify-digest-source.sh ${Arg2} refresh"
	done
fi

# To force the copy from registry to directory with the $Filelist.digest-error input
if [ "$Force" == "True" ]
then
for Image_tag in $(cat $Filelist.digest-error)
  do
    Dir=$(echo $Image_tag| tr ":" "-"| tr "/" "_")
    [ ! -d ./offline/cp4mcm-registry/$Dir ] && mkdir -p ./offline/cp4mcm-registry/$Dir

    FullDir=$(pwd $Dir)"/offline/cp4mcm-registry/$Dir"
    Skopeo_Source=$(skopeo inspect --creds $EXTERNAL_DOCKER_USER:$EXTERNAL_DOCKER_PASSWORD docker://localrepos.infra.asten:5000/$Image_tag |jq .Digest)
    Skopeo_Target=$(skopeo inspect --creds $EXTERNAL_DOCKER_USER:$EXTERNAL_DOCKER_PASSWORD dir:$FullDir |jq .Digest)
    skopeo copy --all --src-creds $EXTERNAL_DOCKER_USER:$EXTERNAL_DOCKER_PASSWORD  docker://localrepos.infra.asten:5000/$Image_tag dir:/var/lib/repo/cp4mcm/2.1.6/offline/cp4mcm-registry/$Dir && \
                        skopeo inspect --creds $EXTERNAL_DOCKER_USER:$EXTERNAL_DOCKER_PASSWORD dir:$FullDir |jq .Digest &
    echo $Dir>> $Filelist.copied


    cd offline/cp4mcm-registry
    tar -cvf $f.tar ./$f
    cd -
    echo "from ocregistry do:"
    echo "cd /var/lib/tempo/cp4mcm-registry"
    echo "wget --no-check-certificate https://localrepos.infra.asten/cp4mcm/2.1.6/offline/cp4mcm-registry/${f}.tar"
    echo "tar -xf ${f}.tar"
    echo "cd  /var/lib/tempo/ && bash skopeo-verify-digest-source.sh ${Arg2} refresh"
  done
fi
