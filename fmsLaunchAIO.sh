#!/bin/bash

# FileMaker Server webroot; only one should be enabled.
WEBROOT="/opt/FileMaker/FileMaker Server/NginxServer/htdocs/httpsRoot/" # NGINX
# WEBROOT="/opt/FileMaker/FileMaker Server/HTTPServer/htdocs/" # Apache

# Specify the size of the FileMakerData and FileMakerBackups volumes; these must match the actual volume sizes.
FMDATA_SIZE=${7}
FMBACKUPS_SIZE=${8}

# FMS installation working directory.
FMSDIR=/fms_install

# SSL renewal installation script.
SSL_SCRIPT="/root/updateFMSCert.sh"

# Flag file created by certbot deploy-hook.
FLAG_FILE=/home/ubuntu/sslDeploy_true

# Retrieve the OS and version number.
OS=`cat /etc/os-release | grep ^NAME | grep -o -P "(?<=\").*(?=\")"`
OSV=`cat /etc/os-release | grep VERSION_ID | grep -o -P "(?<=\").*(?=\.)"`

# Confirm the OS and exit when not Ubuntu.
if [[ ${OS} != "Ubuntu" ]]; then
	echo 'Ubuntu not detected; installer will now quit.'
	exit 1
fi

# Confirm the OS version and exit when not 18 or 20.
if [[ ${OSV} != 18 && ${OSV} != 20 ]]; then
	echo Ubuntu 18 or 20 required for installation. Detected: ${OSV}
	echo Installer will now quit.
	exit 1
fi


# Set license and configuration from arguments.
FQDN=${1}
SSL_EMAIL=${2}
FM_KEY=${3}
USER="admin"
PASS1=${4}
PIN1=${5}

# Upgrade packages and install required packages.
apt update
apt upgrade -y
apt install unzip -y
apt install certbot -y

# Create the working installation directory.
mkdir ${FMSDIR}

# Download the FileMaker license page and save the session cookies.
wget --save-cookies cookies.txt --keep-session-cookies -O filemakerLicense.html https://accounts.filemaker.com/software/license/${FM_KEY}

# Parse the page for the current version of FileMaker Server.
FMSV=`cat filemakerLicense.html | grep -o -P "(?<=/esd/fms_).*(?=_Ubuntu${OSV}.zip)"`

# Parse the page for the session ID used to generate the LicenseCert.fmcert download URL.
SID=`cat filemakerLicense.html | grep -o -P "(?<=../certificate/).*(?=/${FM_KEY})"`

# Download the LicenseCert.fmcert using the custom URL and saved session cookies.
wget --load-cookies cookies.txt -O ${FMSDIR}/LicenseCert.fmcert https://accounts.filemaker.com/software/certificate/${SID}/${FM_KEY}

# Download and extract the FileMaker Server installer and move the installation package to the working installation directory.
wget https://downloads.claris.com/esd/fms_${FMSV}_Ubuntu${OSV}.zip -O ${FMSDIR}/fms_${FMSV}.zip
unzip ${FMSDIR}/fms_${FMSV}.zip
mv filemaker-server-${FMSV}-amd64.deb ${FMSDIR}

# Remove temporary files and clean up installer files.
rm cookies.txt
rm filemakerLicense.html
rm -f Assisted\ Install.txt FMS\ License* README_*


#######################################################################
################## Create the Assisted Install file ###################
#######################################################################
echo "[Assisted Install]

License Accepted=1

Deployment Options=0

Admin Console User=${USER}

Admin Console Password=${PASS1}

Admin Console PIN=${PIN1}

License Certificate Path=/fms_install/LicenseCert.fmcert" > "${FMSDIR}/Assisted Install.txt"
################################# END #################################


#######################################################################
#################### Install FileMaker Server #########################
#######################################################################
export FM_ASSISTED_INSTALL="${FMSDIR}/Assisted Install.txt"
apt install ${FMSDIR}/filemaker-server-${FMSV}-amd64.deb -y
rm "${FMSDIR}/Assisted Install.txt"
certbot certonly --webroot -w '/opt/FileMaker/FileMaker Server/NginxServer/htdocs/httpsRoot/' -d ${FQDN} -m 'admin@codence.com' --no-eff-email --non-interactive --agree-tos
################################# END #################################


#######################################################################
###### Install SSL certificate and renewal installation script. #######
#######################################################################
# Download the SSL automation script and make executable
wget 'https://raw.githubusercontent.com/Codence-Developers/filemakerLinux/main/updateFMSCert.sh' -O "${SSL_SCRIPT}"
chmod +x "${SSL_SCRIPT}"

# Create the crontab schedule to run the script
echo "0 3 * * * \"${SSL_SCRIPT}\"" | crontab -

# Create the post-deploy script and make executable
echo "touch ${FLAG_FILE}" > /etc/letsencrypt/renewal-hooks/deploy/createDeployFlag
echo "chmod 777 ${FLAG_FILE}" >> /etc/letsencrypt/renewal-hooks/deploy/createDeployFlag
chmod +x /etc/letsencrypt/renewal-hooks/deploy/createDeployFlag

# Update the certificate installation script with the user provided values.
sed -i "s/FQDN=\"\"/FQDN=\"${FQDN}\"/g" "${SSL_SCRIPT}"
sed -i "s/FMS_USER=\"\"/FMS_USER=\"${USER}\"/g" "${SSL_SCRIPT}"
sed -i "s/FMS_PASS=\"\"/FMS_PASS=\"${PASS1}\"/g" "${SSL_SCRIPT}"

# Update the certificate installation script with the flag file defined statically above.
sed -i "s|FLAG_FILE=/home/ubuntu/sslDeployFlag|FLAG_FILE=\"${FLAG_FILE}\"|g" "${SSL_SCRIPT}"

# Issue an SSL certificate
certbot certonly --webroot -w "${WEBROOT}" -d "${FQDN}" -m "${SSL_EMAIL}" --no-eff-email --non-interactive --agree-tos

# Create the flag file and run the SSL installation script.
touch "${FLAG_FILE}"
"${SSL_SCRIPT}"
################################# END #################################

#######################################################################
##### Mount and link external FileMaker data and backup volumes. ######
#######################################################################
# Stop FileMaker Server and backup the current filesystem table.
systemctl stop fmshelper
cp /etc/fstab /etc/fstab.bak

# Create the mount points and assign ownership to FileMaker Server.
mkdir /FileMakerData
mkdir /FileMakerBackups
chown fmserver:fmsadmin /FileMakerData
chown fmserver:fmsadmin /FileMakerBackups

# Create and mount the volumes; identified by their disk size.
mkfs -t ext4 "/dev/`lsblk | grep ${FMDATA_SIZE} | awk '{print $1;}'`"
mkfs -t ext4 "/dev/`lsblk | grep ${FMBACKUPS_SIZE} | awk '{print $1;}'`"
mount "/dev/`lsblk | grep ${FMDATA_SIZE} | awk '{print $1;}'`" /FileMakerData
mount "/dev/`lsblk | grep ${FMBACKUPS_SIZE} | awk '{print $1;}'`" /FileMakerBackups

# Configure the volumes to mount at boot; identified by their mount points.
echo "UUID=`lsblk -o +UUID | grep FileMakerData | grep -oE '[^[:space:]]+$'` /FileMakerData ext4 defaults,nofail 0 2" >> /etc/fstab
echo "UUID=`lsblk -o +UUID | grep FileMakerBackups | grep -oE '[^[:space:]]+$'` /FileMakerBackups ext4 defaults,nofail 0 2" >> /etc/fstab

# Create/move the FileMaker Server directories that will be stored on the external volumes and create links in the related FileMaker Server directories.
mv "/opt/FileMaker/FileMaker Server/Data" /FileMakerData
mv "/opt/FileMaker/FileMaker Server/Logs" /FileMakerData
mv /FileMakerData/Data/Backups /FileMakerBackups/Backups
mkdir /FileMakerBackups/Progressive
ln -sv /FileMakerData/Data "/opt/FileMaker/FileMaker Server/Data"
ln -sv /FileMakerData/Logs "/opt/FileMaker/FileMaker Server/Logs"
ln -sv /FileMakerBackups/Backups /FileMakerData/Data/Backups
ln -sv /FileMakerBackups/Progressive /FileMakerData/Data/Progressive

# Recursively assign ownership of the installation directory and mount points to FileMaker Server.
chown -R fmserver:fmsadmin "/opt/FileMaker/FileMaker Server"
chown -R fmserver:fmsadmin /FileMakerData
chown -R fmserver:fmsadmin /FileMakerBackups
################################# END #################################

# Reboot
reboot now
