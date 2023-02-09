#!/bin/bash

# This launch script minimizes the user data needed when launching a new instance.
# Required arguments: ElasticIP FQDN SSL_Email FMS_License Admin_Password Admin_PIN
# Arguments must be provided in the specified order.

apt install unzip -y
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update
aws ec2 associate-address --instance-id $(curl -s http://169.254.169.254/latest/meta-data/instance-id) --public-ip ${1}
wget 'https://raw.githubusercontent.com/Codence-Developers/filemakerLinux/main/fmsLaunch.sh' -O /root/fmsLaunch.sh
chmod +x /root/fmsLaunch.sh
/root/fmsLaunch.sh ${2} ${3} ${4} ${5} ${6} ${7} ${8}

# User Data:
#   #!/bin/bash
#   wget 'https://raw.githubusercontent.com/Codence-Developers/filemakerLinux/main/launch.sh' -O /root/launch.sh
#   chmod +x /root/launch.sh
#   /root/launch.sh <ElasticIP> <FQDN> <SSL_Email> <FMS_License> <Admin_Password> <Admin_PIN> <FMData_Size> <FMBackups_Size>