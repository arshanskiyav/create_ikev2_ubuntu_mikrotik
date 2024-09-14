#!/bin/bash
if [[ $EUID -ne 0 ]]; then
        echo "You should use root account or sudo to connect."
        exit 1
fi

check_install_package(){
        package="$1"
        state=$(dpkg -s $package 2>/dev/null| grep "install ok installed")
        if [[ "$state" == "" ]]
        then
                echo "$package not found. Please install $package."
                read -p "Install $package now? (y/n): " -n 1 -r
                if [[ ! $REPLY =~ ^[Yy]$ ]]
                then
                        exit 1
                fi
                apt install $package -y
        else
                echo -e "\t$package found."
        fi
}
check_file_exist(){
        chk_file="$1"
        if [ ! -f "$chk_file" ]
        then
                echo -e "\n\tFile $chk_file not found.\n\tExit. \n"
                exit 1
        fi
}

get_param(){
        settings="$1"
        name_param="$2"
        res=$(awk -v param="$name_param" -F "=" '$1 == param {print $2}' $settings | sed -e 's/\\/\//g')
        echo "$res"
}

echo -e "\nInitializing settings..."
settings="${PWD}/settings.ini"

sed -i.bak 's/\r$//' $settings

check_file_exist $settings

FileP12=${PWD}/$(get_param $settings "FileP12")
check_file_exist "$FileP12"
FileCA=${PWD}/$(get_param $settings "FileCA")
check_file_exist "$FileCA"
ConnectionName=$(get_param $settings "ConnectionName")
ServerAddress=$(get_param $settings "ServerAddress")

read -p "Please put key for PKCS#12 container: " -s -r pswd
if [[ "$pswd" == "" ]]
then
        echo "Password not entered!"
        exit 1
fi

subjectAltName=$(openssl pkcs12 -in "$FileP12" -nodes -passin pass:"$pswd" | openssl x509 -noout -ext subjectAltName | awk -F":" '/DNS/ {print $2}')
if [[ "$subjectAltName" == "" ]]
then
        echo -e "\n\tThe certificate file does not contain subjectAltName\n\tExit"
        exit 1
fi
echo -e "\n\tThe installed alternative name is $subjectAltName"

echo "Check installed packages..."
check_install_package strongswan
check_install_package resolvconf
#check_install_package libcharon-extra-plugins

echo "Installing configuration"

mkdir -p /etc/ipsec.d/certs
nFileP12="/etc/ipsec.d/certs/client.$ServerAddress.p12"
cp "$FileP12" "$nFileP12"
check_file_exist "$nFileP12"
echo -e "\tClient certificate installed successfully to $nFileP12"


mkdir -p /etc/ipsec.d/cacerts
nFileCA="/etc/ipsec.d/cacerts/$ServerAddress.pem"
cp "$FileCA" "$nFileCA"
check_file_exist "$nFileCA"
echo -e "\tRoot certificate installed successfully to $nFileCA"



cat > /etc/ipsec.conf <<- EOCONF

conn $ConnectionName
# Setting up the server side
    rightsubnet=10.110.0.0/16
    right=$ServerAddress
    rightid=fqdn:$ServerAddress
# Setting up the client side
    leftsourceip=%config
    leftdns=%config
#    left=%any
    leftid=fqdn:$subjectAltName
    leftcert=$nFileP12
#    leftid=fqdn:$ConnectionName
# Tunnel setup
    authby=rsasig
# For autostart use this parameter
#    auto=start
# With this parameter, the tunnel does not rise automatically.
# The command must be executed sudo ipsec up $ConnectionName
    auto=add
    ike=aes256-prfsha1-sha1-modp2048
    keyexchange=ikev2
    esp=aes256-sha256-ecp384
    type=tunnel
EOCONF


cat > /etc/ipsec.secrets << EOCONF
 : P12 $nFileP12 "$pswd"
EOCONF
chmod 600 /etc/ipsec.secrets
systemctl restart ipsec

sleep 3
ipsec up $ConnectionName

echo -e "\nEND"

exit 0
