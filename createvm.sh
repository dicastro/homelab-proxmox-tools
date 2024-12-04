#!/bin/bash

mkdir -p sshkeys

SUPPORTED_UBUNTU_VERSIONS=(
  "noble:24.04"
)

SSH_KEYS_DIR="./sshkeys"

show_help() {
  echo "Usage: $0 [options]"
  echo "Options:"
  echo "  --id <ID>                       ID for the VM (required)"
  echo "  --name <NAME>                   Name for the VM (required)"
  echo "  --ram <number>                  RAM (in GB) assignated to the VM"
  echo "  --cores <number>                Number of cores of the VM"
  echo "  --disk-size <number>            Size (in GB) of the VM disk"
  echo "  --storage <STORAGE>             Which storage will be used to host the VM disk"
  echo "  --user <USERNAME>               User created in the VM"
  echo "  --pass <PASSWORD>               Password for the user in the VM"
  echo "  --upgrade-packages              Packages will be upgraded after first start of the VM"
  echo "  --ubuntu-version <VERSION_NAME> Name of the Ubuntu version for the VM (e.g. Noble)"
  echo "  --new-ssh-key                   New SSH key should be generated"
  echo "  --new-ssh-key-name <NAME>       SSH key name"
  echo "  --use-ssh-key <NAME>            Name of an already existing SSH key"
  echo "  --dhcp                          Use dhcp in the VM"
  echo "  --ip <IP>                       Static IP of the VM"
  echo "  --gatewai-ip <IP>               Gateway IP for the VM"
  echo "  --dns-servers <IP>:<IP>         DNS servers for the VM"
  echo "  --help                          Display this help message"
}

print_error() {
  local message="$1"
  local show_errors="$2"

  if [[ "$show_errors" == "true" ]]; then
    echo "$message" >&2
  fi
}

validate_vm_id() {
  local id="$1"
  local show_errors="${2:-false}"

  if [[ "${id}" =~ ^[0-9]+$ ]] && ((id >= 100 && id < 1000)); then
    if ! qm status "${id}" &>/dev/null; then
      return 0
    else
      print_error "Id '${id}' already in use. Please choose a different id." "$show_errors"
      return 1
    fi
  else
    print_error "Invalid input. Id has to be a number between 100 and 999. Please provide a valid id." "$show_errors"

    return 1
  fi
}

validate_vm_name() {
  local name="$1"
  local show_errors="${2:-false}"

  if [[ -z "${name}" ]]; then
    print_error "VM name cannot be empty. Please provide a valid name." "$show_errors"
    return 1
  fi

  local vm_names=$(qm list | awk 'NR > 1 {print $2}')

  if echo "${vm_names}" | grep -qx "${name}"; then
    print_error "VM name '${name}' is already in use. Please choose a different name." "$show_errors"
    return 1
  fi

  return 0
}

validate_ram() {
  local ram="$1"
  local max_proxmox_ram="$2"
  local show_errors="${3:-false}"

  if [[ "${ram}" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    local ram_gt_zero=$(echo "${ram} > 0" | bc -l)
    local ram_le_max=$(echo "$ram <= ${max_proxmox_ram}" | bc -l)

    if [[ "${ram_gt_zero}" -eq 1 && "${ram_le_max}" -eq 1 ]]; then
      return 0
    fi
  fi

  print_error "Invalid input. RAM has to be an integer or decimal number > 0 and <= ${max_proxmox_ram}. Please provide a valid RAM value" "$show_errors"
  return 1
}

validate_cores() {
  local cores="$1"
  local max_proxmox_cores="$2"
  local show_errors="${3:-false}"

  if [[ "${cores}" =~ ^[0-9]+$ ]]; then
    local cores_gt_zero=$(echo "${cores} > 0" | bc -l)
    local cores_le_max=$(echo "${cores} <= ${max_proxmox_cores}" | bc -l)

    if [[ "${cores_gt_zero}" -eq 1 && "${cores_le_max}" -eq 1 ]]; then
      return 0
    fi
  fi

  print_error "Invalid input. CPU cores has to be a number >= 1 and <= ${max_proxmox_cores}. Please provide a valid number of CPU cores value" "$show_errors"
  return 1
}

validate_disk_size() {
  local disk_size="$1"
  local show_errors="${2:-false}"

  if [[ "${disk_size}" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    local disk_size_gt_zero=$(echo "${disk_size} > 0" | bc -l)

    if [[ "${disk_size_gt_zero}" -eq 1 ]]; then
      return 0
    fi
  fi
  
  print_error "Invalid input. Disk size has to be an integer or decimal number > 0. Please provide a valid disk size value" "$show_errors"
  return 1
}

validate_storage() {
  local storage="$1"
  local show_errors="${2:-false}"

  if [[ -z "${storage}" ]]; then
    print_error "Storage cannot be empty. Please provide a valid storage from the available ones." "$show_errors"
    return 1
  fi

  if pvesm list "$1" &>/dev/null; then
    return 0
  else
    print_error "Storage '${storage}' not valid. Please provide a valid storage from the available ones." "$show_errors"
    return 1
  fi
}

validate_user() {
  local user="$1"
  local show_errors="${2:-false}"

  if [[ -z "$user" ]]; then
    print_error "User name cannot be empty. Please provide a valid name." "$show_errors"
    return 1
  else
    return 0
  fi
}

validate_yes_no() {
  local yn="$1"
  local show_errors="${2:-false}"
  
  if [[ "${yn}" =~ ^(y|Y|n|N)$ ]]; then
    return 0
  else
    print_error "Invalid anser. Please provide a valid value." "$show_errors"
    return 1
  fi
}

get_supported_ubuntu_versions_prompt_message() {
  local prompt_message=""
  
  for version in "${SUPPORTED_UBUNTU_VERSIONS[@]}"; do
    IFS=':' read -r codename version_number <<< "$version"
    prompt_message+="$codename ($version_number) "
  done
  
  echo "${prompt_message}"
}

validate_ubuntu_codename() {
  local ubuntu_codename="$1"
  local available_ubuntu_codenames="$2"
  local show_errors="${3:-false}"

  if [[ " $available_ubuntu_codenames " =~ " $ubuntu_codename " ]]; then
    return 0
  else
    if [[ "$show_errors" == "true" ]]; then
      echo "Invalid Ubuntu version. Pleas provide a valid ubuntu version" >&2
    fi
    return 1
  fi
}

get_ubuntu_download_url() {
  local codename="$1"

  for version in "${SUPPORTED_UBUNTU_VERSIONS[@]}"; do
    IFS=':' read -r supported_codename version_number <<< "$version"

    if [[ "$codename" == "$supported_codename" ]]; then
      echo "https://cloud-images.ubuntu.com/releases/${codename}/release/ubuntu-${version_number}-server-cloudimg-amd64.img"
      return 0
    fi
  done

  echo "Error: Unsupported Ubuntu codename '$codename'" >&2
  return 1
}

check_and_download_ubuntu_image() {
  local ubuntu_codename="$1"
  
  local image_url=$(get_ubuntu_download_url "${ubuntu_codename}")
  local image_name=$(basename "$image_url")
  
  local iso_storage_path="/var/lib/vz/template/iso"
  local image_path="$iso_storage_path/$image_name"

  if [[ -f "${image_path}" ]]; then
    echo "Image '$image_name' already exists in Proxmox storage." >&2
    echo "${image_path}"
    return 0
  else
    echo "Downloading '${image_name}'..." >&2
    curl -s -o "${image_path}" "$image_url"
    
    if [[ $? -eq 0 ]]; then
      echo "Image downloaded successfully." >&2
      echo "${image_path}"
      return 0
    else
      echo "Error: Failed to download image." >&2
      return 1
    fi
  fi
}

validate_existing_ssh_key_name() {
  local key_name="$1"
  local show_errors="${2:-false}"

  if [[ -z "${key_name}" ]]; then
    print_error "Key name cannot be empty. Please provide a valid key name from the available ones." "$show_errors"
    return 1
  fi

  if [[ -d "${SSH_KEYS_DIR}/${key_name}" ]]; then
    return 0
  else
    print_error "SSH key '${key_name}' does not exist. Please provide a valid key name from the available ones" "$show_errors"
    return 1
  fi
}

validate_non_existing_ssh_key_name() {
  local key_name="$1"
  local show_errors="${2:-false}"

  if [[ -z "${key_name}" ]]; then
    print_error "Key name cannot be empty. Please provide a valid non existing key name." "$show_errors"
    return 1
  fi

  if [[ -d "${SSH_KEYS_DIR}/${key_name}" ]]; then
    print_error "SSH key '${key_name}' already exists. Please provide a valid non existing key name" "$show_errors"
    return 1
  else
    return 0
  fi
}

get_available_ssh_keys() {
  local valid_keys=()
  
  if [[ -d "$SSH_KEYS_DIR" ]]; then
    for dir in "${SSH_KEYS_DIR}"/*; do
      if [[ -d "$dir" ]]; then
        local key_name=$(basename "$dir")

        if [[ -f "${dir}/id_${key_name}" && -f "${dir}/id_${key_name}.pub" ]]; then
          valid_keys+=("$key_name")
        fi
      fi
    done
  fi

  echo "${valid_keys[@]}"
}

generate_ssh_key() {
  local key_name="$1"

  mkdir -p "${SSH_KEYS_DIR}/${key_name}"
  ssh-keygen -t rsa -b 4096 -f "${SSH_KEYS_DIR}/${key_name}/id_${key_name}" -q -N ""
  
  echo "SSH key '${key_name}' generated successfully"
}

validate_ip() {
  local ip="$1"
  local show_errors="${2:-false}"

  if [[ "${ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    return 0
  else
    print_error "Wrong format for IP '${ip}'. Please provide a valid IP" "$show_errors"
    return 1
  fi
}

validate_dns_servers() {
  local dns_servers="$1"
  local show_errors="${2:-false}"
  local separator="${3:- }"

  IFS="$separator" read -ra dns_array <<< "$dns_servers"

  if [[ "${#dns_array[@]}" -eq 0 ]]; then
    print_error "No DNS servers provided. Please provide valid DNS servers." "$show_errors"
    return 1
  fi

  for dns in "${dns_array[@]}"; do
    if [[ ! "${dns}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      print_error "Wrong format for DNS server '${dns}'. Please provide valid DNS servers" "$show_errors"
      return 1
    fi
  done

  return 0
}


prompt_input() {
  local prompt="$1"
  local default_value="$2"
  shift 2
  local validate_func="$1"
  shift 1
  local input

  while true; do
    if [[ -n "${default_value}" ]]; then
      read -p "${prompt} [${default_value}]: " input
      input="${input:-$default_value}"
    else
      read -p "${prompt}: " input
    fi

    if [[ -n "${validate_func}" ]]; then
      if "${validate_func}" "${input}" "$@"; then
        echo "${input}"
        return 0
      fi
    else
      echo "${input}"
      return 0
    fi
  done
}


create_vm() {
  local id="$1"
  local name="$2"
  local ram="$3"
  local cores="$4"
  local ubuntu_iso="$5"
  local storage="$6"
  local disk_size="$7"
  local user="$8"
  local pass="$9"
  local ssh_key_name="${10}"
  local upgrade_packages="${11}"
  local network_config="${12}"
  local ip="${13}"
  local gateway_ip="${14}"
  local dns_servers="${15}"

  # Create VM
  qm create "${id}" --name "${name}" --memory "$((ram * 1024))" --cores "${cores}" --cpu "x86-64-v2-AES" --net0 virtio,bridge=vmbr0,firewall=1

  # Import ISO as disk
  import_output=$(qm importdisk "${id}" "${ubuntu_iso}" "${storage}" 2>&1)

  disk_id=$(echo "$import_output" | grep "Successfully imported disk" | awk -F"'" '{print $2}' | cut -d':' -f2-)

  if [[ -z "$disk_id" ]]; then
    echo "Failed to import disk. Check the importdisk command output."
    exit 1
  fi

  # Configure VM storage
  qm set "${id}" --scsihw virtio-scsi-pci --scsi0 "$disk_id"
  qm set "${id}" --boot c --bootdisk scsi0       # Set boot order to only boot from the imported disk
  qm set "${id}" --ide2 "${storage}:cloudinit"   # Add cloud-init drive
  qm set "${id}" --boot c --bootdisk scsi0       # Set boot order to only boot from the cloud-init drive

  # Resize disk
  qm resize "${id}" scsi0 "${disk_size}G"

  # Configure cloud-init settings
  qm set "${id}" --ciuser "${user}" --cipassword "${pass}"
  qm set "${id}" --sshkey "${SSH_KEYS_DIR}/${ssh_key_name}/id_${ssh_key_name}.pub"
  if [[ "${upgrade_packages}" =~ ^(y|Y)$ ]]; then
    qm set "${id}" --ciupgrade 1
  fi

  # Network configuration
  if [[ "$network_config" == "dhcp" ]]; then
    qm set "${id}" --ipconfig0 ip=dhcp
  else
    qm set "${id}" --ipconfig0 ip="$ip/24",gw="$gateway_ip"
  fi
  qm set "${id}" --nameserver "$dns_servers"

  echo "VM ${id} (${name}) created and configured with cloud-init."
}


DEFAULT_RAM="2"
DEFAULT_CORES="1"
DEFAULT_DISK_SIZE="10"
DEFAULT_USER="root"
DEFAULT_PASSWORD_MESSAGE="same as username"
DEFAULT_UPGRADE_PACKAGES="Y"
DEFAULT_UBUNTU_VERSION="noble"
DEFAULT_DHCP="N"
DEFAULT_GATEWAY_IP="192.168.86.1"
DEFAULT_DNS_SERVERS="1.1.1.1 8.8.8.8"


ID=""
NAME=""
RAM=""
CORES=""
DISK_SIZE=""
STORAGE=""
USER=""
PASS=""
UPGRADE_PACKAGES=""
UBUNTU_VERSION=""
NEW_SSH_KEY=""
NEW_SSH_KEY_NAME=""
USE_SSH_KEY=""
DHCP=""
IP=""
GATEWAY_IP=""
DNS_SERVERS=""

SSH_KEY_NAME=""
NETWORK_CONFIG=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --id) ID="$2"; shift ;;
    --name) NAME="$2"; shift ;;
    --ram) RAM="$2"; shift ;;
    --cores) CORES="$2"; shift ;;
    --disk-size) DISK_SIZE="$2"; shift ;;
    --storage) STORAGE="$2"; shift ;;
    --user) USER="$2"; shift ;;
    --pass) PASS="$2"; shift ;;
    --upgrade-packages) UPGRADE_PACKAGES="Y" ;;
    --ubuntu-version) UBUNTU_VERSION="$2"; shift ;;
    --new-ssh-key) NEW_SSH_KEY="Y" ;;
    --new-ssh-key-name) NEW_SSH_KEY_NAME="$2"; shift ;;
    --use-ssh-key) USE_SSH_KEY="$2"; shift ;;
    --dhcp) DHCP="Y" ;;
    --ip) IP="$2"; shift ;;
    --gateway-ip) GATEWAY_IP="$2"; shift ;;
    --dns-servers) DNS_SERVERS="$2"; shift ;;
    --help) show_help; exit 0 ;;
    *) echo "Unknown parameter: $1"; show_help; exit 1 ;;
  esac
  shift
done


if ! validate_vm_id "${ID}"; then
  ID=$(prompt_input "Enter VM ID - Min: 100 - Max: 999" "" validate_vm_id "true")
fi

if ! validate_vm_name "${NAME}"; then
  NAME=$(prompt_input "Enter VM name" "" validate_vm_name "true")
fi

# Fetch max RAM available on Proxmox
MAX_PROXMOX_RAM=$(pvesh get /nodes/$(hostname)/status --output-format yaml | grep -A 3 "memory" | grep "total" | awk '{print int($2 / (1024 * 1024 * 1024))}')

if ! validate_ram "${RAM}" "${MAX_PROXMOX_RAM}"; then
  RAM=$(prompt_input "Enter RAM size (GB) - Max: ${MAX_PROXMOX_RAM}" "${DEFAULT_RAM}" validate_ram "${MAX_PROXMOX_RAM}" "true")
fi

# Fetch max CPU cores available on Proxmox
MAX_PROXMOX_CORES=$(pvesh get /nodes/$(hostname)/status --output-format yaml | grep "cores" | awk '{print $2}')

if ! validate_cores "${CORES}" "${MAX_PROXMOX_CORES}"; then
  CORES=$(prompt_input "Enter number of CPU cores - Max: ${MAX_PROXMOX_CORES}" "${DEFAULT_CORES}" validate_cores "${MAX_PROXMOX_CORES}" "true")
fi

if ! validate_disk_size "${DISK_SIZE}"; then
  DISK_SIZE=$(prompt_input "Enter total disk size (GB)" "${DEFAULT_DISK_SIZE}" validate_disk_size "true")
fi

# Fetch available storages in Proxmox
AVAILABLE_STORAGES=$(pvesm status | awk '{if (NR>1) print $1}' | tr '\n' ' ')

# Default values (adjust storage to be the first available storage if `local-lvm` is not valid)
DEFAULT_STORAGE="local-lvm"
if ! echo "${AVAILABLE_STORAGES}" | grep -qw "${DEFAULT_STORAGE}"; then
  DEFAULT_STORAGE=$(echo "${AVAILABLE_STORAGES}" | awk '{print $1}')
fi

if ! validate_storage "${STORAGE}"; then
  STORAGE=$(prompt_input "Enter storage for VM disk (Available: ${AVAILABLE_STORAGES})" "${DEFAULT_STORAGE}" validate_storage "true")
fi

if ! validate_user "${USER}"; then
  USER=$(prompt_input "Enter username" "${DEFAULT_USER}" validate_user "true")
fi

# Password prompt with secret input, showing a message for default option
read -s -p "Enter password [${DEFAULT_PASSWORD_MESSAGE}]: " read_password
PASS="${read_password:-$USER}"
echo  # To add a newline after the password prompt


if ! validate_yes_no "${UPGRADE_PACKAGES}"; then
  UPGRADE_PACKAGES=$(prompt_input "Upgrade packages on first boot? (Y/n)" "${DEFAULT_UPGRADE_PACKAGES}" validate_yes_no "true")
fi

AVAILABLE_SUPPORTED_UBUNTU_VERSIONS=$(get_supported_ubuntu_versions_prompt_message | awk '{print $1}')

if ! validate_ubuntu_codename "${UBUNTU_VERSION}" "${AVAILABLE_SUPPORTED_UBUNTU_VERSIONS}"; then
  UBUNTU_VERSION=$(prompt_input "Select ubuntu version (Available: ${AVAILABLE_SUPPORTED_UBUNTU_VERSIONS})" "${DEFAULT_UBUNTU_VERSION}" validate_ubuntu_codename "${AVAILABLE_SUPPORTED_UBUNTU_VERSIONS}" "true")
fi

UBUNTU_ISO=$(check_and_download_ubuntu_image "${UBUNTU_VERSION}" || exit 1)


if [[ "${NEW_SSH_KEY}" =~ ^[Yy]$ ]]; then
  if ! validate_existing_ssh_key_name "${NEW_SSH_KEY_NAME}"; then
    SSH_KEY_NAME=$(prompt_input "Enter a name for the new SSH key" "" validate_non_existing_ssh_key_name "true")
  else
    SSH_KEY_NAME="${NEW_SSH_KEY_NAME}"
  fi

  generate_ssh_key "$SSH_KEY_NAME"
else
  available_keys=($(get_available_ssh_keys))
  
  if [[ -n "$USE_SSH_KEY" ]]; then
    if [[ ${#available_keys[@]} -eq 0 ]]; then
      echo "There are no existing valid SSH keys, so the provided one is not valid. New SSH key will be created"

      SSH_KEY_NAME=$(prompt_input "Enter a name for the new SSH key" "" validate_non_existing_ssh_key_name "true")

      generate_ssh_key "$SSH_KEY_NAME"
    else
      if ! validate_existing_ssh_key_name "${USE_SSH_KEY}"; then
        SSH_KEY_NAME=$(prompt_input "Select SSH key (${available_keys[@]})" "${available_keys[0]}" validate_existing_ssh_key_name "true")
      else
        SSH_KEY_NAME="${USE_SSH_KEY}"
      fi
    fi
  else
    if [[ ${#available_keys[@]} -eq 0 ]]; then
      echo "There are no existing valid SSH keys. New SSH key will be created"

      SSH_KEY_NAME=$(prompt_input "Enter a name for the new SSH key" "" validate_non_existing_ssh_key_name "true")

      generate_ssh_key "$SSH_KEY_NAME"
    else
      SSH_KEY_NAME=$(prompt_input "Select SSH key (Available: ${available_keys[@]})" "${available_keys[0]}" validate_existing_ssh_key_name "true")
    fi
  fi
fi

if ! validate_yes_no "${DHCP}"; then
  DHCP=$(prompt_input "Get IP through DHCP? (y/N)" "${DEFAULT_DHCP}" validate_yes_no "true")
fi

if [[ "${DHCP}" =~ ^[Yy]$ ]]; then
  NETWORK_CONFIG="dhcp"
else
  if ! validate_ip "${IP}"; then
    IP=$(prompt_input "Enter static IP" "" validate_ip "true")
  fi

  if ! validate_ip "${GATEWAY_IP}"; then
    GATEWAY_IP=$(prompt_input "Enter gateway IP" "${DEFAULT_GATEWAY_IP}" validate_ip "true")
  fi

  if ! validate_dns_servers "${DNS_SERVERS}" "false" ":"; then
    DNS_SERVERS=$(prompt_input "Enter DNS servers (space-separated)" "${DEFAULT_DNS_SERVERS}" validate_dns_servers "true" " ")
  fi
fi


echo "About to create vm with:"
echo "  - ID:      ${ID}"
echo "  - Name:    ${NAME}"
echo "  - RAM:     ${RAM}GB"
echo "  - Cores:   ${CORES}"
echo "  - Disk:    ${DISK_SIZE}GB"
echo "  - Storage: ${STORAGE}"
echo "  - User:    ${USER}"
echo "  - Pass:    *****"
echo "  - Ugrade:  ${UPGRADE_PACKAGES}"
echo "  - Ubuntu:  ${UBUNTU_VERSION}"
echo "  - ISO:     ${UBUNTU_ISO}"
echo "  - SSH:     ${SSH_KEY_NAME}"

if [[ "${DHCP}" =~ ^[Yy]$ ]]; then
  echo "  - DHCP:    yes"
else
  echo "  - IP:      ${IP}"
  echo "  - Gateway: ${GATEWAY_IP}"
  echo "  - DNS:     ${DNS_SERVERS}"
fi

create_vm "${ID}" "${NAME}" "${RAM}" "${CORES}" "${UBUNTU_ISO}" "${STORAGE}" "${DISK_SIZE}" "${USER}" "${PASS}" "${SSH_KEY_NAME}" "${UPGRADE_PACKAGES}" "${NETWORK_CONFIG}" "${IP}" "${GATEWAY_IP}" "${DNS_SERVERS}"
