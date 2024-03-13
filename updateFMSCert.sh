#!/bin/bash

################################################
############ User Defined Variables ############
################################################
# Fully qualified domain name.
FQDN=""

# Admin Console credentials
FMS_USER=""
FMS_PASS=""

# Flag file created by certbot deploy-hook.
FLAG_FILE=/home/ubuntu/sslDeploy_true
################################################


################################################
############ Default FileMaker Path ############
################################################
# FileMaker Server installation directory.
FMS="/opt/FileMaker/FileMaker Server"
################################################


# If [the flag file does not exist] exit the script.
if [ ! -f "$FLAG_FILE" ]; then
    exit 0
fi

# Delete the flag file.
rm "$FLAG_FILE"

# Copy the certificate to the FileMaker CStore and set the private key permissions.
cp "/etc/letsencrypt/live/${FQDN}/fullchain.pem" "${FMS}/CStore/fullchain.pem"
cp "/etc/letsencrypt/live/${FQDN}/privkey.pem" "${FMS}/CStore/privkey.pem"
chmod 640 "${FMS}/CStore/privkey.pem"

# Copy the default server certificate; FileMaker Server will throw an error otherwise.
mv "${FMS}/CStore/server.pem" "${FMS}/CStore/serverKey-old.pem"

# Delete the installed certificate.
fmsadmin certificate delete --yes -u ${FMS_USER} -p ${FMS_PASS}

# Import the new certificate.
fmsadmin certificate import "${FMS}/CStore/fullchain.pem" --keyfile "${FMS}/CStore/privkey.pem" -y -u ${FMS_USER} -p ${FMS_PASS}

# Close the FileMaker databases.
fmsadmin close -u ${FMS_USER} -p ${FMS_PASS} -m "Databases will close in two minutes for scheduled maintenance." -t 120

# Provide time for the databases to close. Two minutes for the user warning and two minutes to close the databases.
sleep 240

# Restart the FileMaker Server service
sudo systemctl restart fmshelper

# Provide the service time to gracefully stop and start
sleep 300

# Start the database server
fmsadmin start server -u ${FMS_USER} -p ${FMS_PASS}

# Provide the database server time to start
sleep 60

# Open databases
fmsadmin open -u ${FMS_USER} -p ${FMS_PASS}
