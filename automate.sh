#!/bin/bash
#Create the nginx-service folder if it doesn't exist
nginx_service_dir="$HOME/dev/nginx-service"
if [ ! -d "$nginx_service_dir" ]; then
    mkdir -p "$nginx_service_dir"
fi
# Create the certs directory if it doesn't exist
certs_dir="$nginx_service_dir/certs"
mkdir -p "$certs_dir"

# Save the dirname into a variable
dirname="$(pwd)"



# Specify the path to the hosts file
hosts_file="/etc/hosts"

# Check if the hosts file exists
if [ ! -e "$hosts_file" ]; then
    echo "Error: Hosts file $hosts_file not found."
    exit 1
fi

# Check if at least two arguments are provided
if [ $# -lt 2 ]; then
    echo "Usage: $0 <ip_address> <domain1>:<port> <domain2>:<port> ..."
    exit 1
fi

# Get the IP address from the first argument
ip_address="$1"
shift  # Remove the first argument from the list
#for each element passed split into list  the port api.kartowka.local:8000 -> api.kartowka.local 8000
# Loop through the arguments and validate the format
# Validate IP address format
if [[ ! $ip_address =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Invalid IP address format."
    exit 1
fi

# Declare an array to store the ports
declare -a ports_array

# Iterate over the rest of the arguments (domain:port pairs)
for arg in "$@"; do
    if [[ ! $arg =~ ^[a-zA-Z0-9.-]+:[0-9]+$ ]]; then
        echo "Error: Invalid domain:port format for argument: $arg"
        exit 1
    fi
    # Split domain:port into separate variables
        domain=$(echo "$arg" | cut -d':' -f1)
        port=$(echo "$arg" | cut -d':' -f2)

    ports_array+=("$port")
    done
# Loop through the array of domains
i=0
for domain in "$@"; do
    # Check if the entry already exists
    domain=$(echo "$domain" | cut -d':' -f1)
    if grep -qF "$domain" "$hosts_file"; then
        echo "Error: Hosts entry already exists in $hosts_file for domain $domain"
    else
        # Append the new hosts entry to the file
        echo sudo -S bash -c "#Added by automate.sh script at $(date)" >> "$hosts_file"
        echo sudo -S bash -c "$ip_address    $domain" >> "$hosts_file"
        echo "Hosts entry added to $hosts_file for domain $domain"
    fi
done
    # Split the domain to only have the domain name without subdomains
    if [ -z "$1" ]; then
        echo "Error: Domain name not provided."
        exit 1
    fi
    echo $1
    # Validate the format of the domain name
    # if [[ ! "$1" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    #     echo "Error: Invalid domain name format."
    #     exit 1
    # fi

    domain_name=$(echo "$domain" | cut -d':' -f1 | awk -F'.' '{print $(NF-1) "." $NF}')
    # Clone the repository
    git clone https://github.com/FiloSottile/mkcert

    # Change directory to the repository
    cd mkcert

    #check if go is installed by the uname command
    if [ "$(uname)" == "Linux" ]; then
        if ! command -v go &> /dev/null; then
            sudo apt install golang
        fi
    elif [ "$(uname)" == "Darwin" ]; then
        if ! command -v go &> /dev/null; then
            brew install golang
        fi
    else
        echo "Error: Unsupported operating system."
        exit 1
    fi
    # Build the mkcert tool
    if ! go build -ldflags "-X main.Version=$(git describe --tags)"; then
        echo "Error: Failed to build mkcert tool."
        exit 1
    fi
    # Generate the certificate using mkcert
    if ! ./mkcert "*.$domain_name"; then
        echo "Error: Failed to generate certificate for domain $domain_name."
        exit 1
    fi

    # Copy the certificates to the folder of the automate script
    cp *"$domain_name"* "$certs_dir"
    # Store cert key in variable
    cert_key=$(ls *"$domain_name"* | grep -i pem | sed -n 1p)
    cert_pem=$(ls *"$domain_name"* | grep -i pem | sed -n 2p)
    # Get private IP address into variable

    if [ "$(uname)" == "Linux" ]; then
    private_ip=$(hostname -I | awk '{print $1}')

    # Check if the operating system is macOS
    elif [ "$(uname)" == "Darwin" ]; then
        private_ip=$(ipconfig getifaddr en0)

    # Handle other operating systems if needed
    else
        echo "Unsupported operating system."
        exit 1
    fi
    # remove the certs files from the mkcert folder
    rm *"$domain_name"*
    # Change back to the original directory
    cd $nginx_service_dir
    echo "Certificate generated and copied for domain *.$domain_name"
    # Create the nginx configuration file forEach domain in @ from template using variables
    index=0
    echo "http {" >> "nginx.conf"
    for domain in "$@"; do
        # Split domain:port into separate variables
        d=$(echo "$domain" | cut -d':' -f1)
        p=$(echo "$domain" | cut -d':' -f2)
        sed -e "s/{{SERVER_NAME}}/$d/g" -e "s/{{CERT_PEM}}/$cert_pem/g" -e "s/{{CERT_KEY}}/$cert_key/g" -e "s/{{PRIVATE_IP}}/$private_ip/g" -e "s/{{PORT}}/$p/g" "$dirname/nginx.temp.conf" >> "$nginx_service_dir/nginx.conf"
        ((index++))
    done
    echo "}" >> "nginx.conf"
    echo "events {}" >> "nginx.conf"
    cp "$dirname/docker-compose.yml" "$nginx_service_dir"

