#!/bin/bash
apt install unzip -y
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update
aws ec2 associate-address --instance-id $(curl -s http://169.254.169.254/latest/meta-data/instance-id) --public-ip ${1}
wget 'https://raw.githubusercontent.com/Codence-Developers/filemakerLinux/main/fmsLaunch.sh' -O /root/fmsLaunch.sh
chmod +x /root/fmsLaunch.sh
/root/fmsLaunch.sh ${2} ${3} ${4} ${5} ${6}