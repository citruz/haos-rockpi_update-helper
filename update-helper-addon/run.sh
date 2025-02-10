#!/usr/bin/with-contenv bashio

set +e

GITHUB_REPO="citruz/haos-rockpi"
RELEASES_URL="https://api.github.com/repos/${GITHUB_REPO}/releases"

TMP_IMG="/tmp/tmp.img"
TMP_MOUNT="/tmp/tmp"

# Fetch the asset json from GitHub
# Arguments: $1 version, $2 board
function fetch_asset() {
    local version="${1}"
    local board="${2}"
    local response
    local asset

    bashio::log.trace "${FUNCNAME[0]}" "$@"
    
    response=$(curl -s -f "${RELEASES_URL}")
    if [ $? -ne 0 ]; then
        bashio::log.debug "${response}"
        bashio::exit.nok "Error fetching releases from ${RELEASES_URL}"
    fi

    # Filter for the correct one and extract download url
    asset=$(echo "${response}" | jq -r \
        --arg filter "${board}-${version}" \
        '.[] | .assets[] | select(.name | contains($filter) and endswith(".raucb"))')

    if [ -z "${asset}" ]; then
        bashio::log.trace "${response}"
        bashio::exit.nok "No suitable release found for board '${board}' and version '${version}'."
    fi

    echo "${asset}"
}

# get the download url from the asset
# Arguments: $1 asset
function get_asset_url() {
    local asset="$*"
    local url

    bashio::log.trace "${FUNCNAME[0]}" "$@"
        
    url=$(echo "${asset}" | jq -r \
        '.browser_download_url')

    if [ -z "${url}" ]; then
        bashio::exit.nok "Error extracting asset url."
    fi

    echo "${url}"
}

# get the size from the asset
# Arguments: $1 asset
function get_asset_size() {
    local asset="$*"
    local url

    bashio::log.trace "${FUNCNAME[0]}" "$@"
        
    url=$(echo "${asset}" | jq -r \
        '.size')

    if [ -z "${url}" ]; then
        bashio::exit.nok "Error extracting asset size."
    fi

    echo "${url}"
}

# Create a temp image with appropriate size and mount
# Arguments: $1 size in Megabyte
function create_tmp_image_and_mount() {
    local size="${1}"
    local free

    bashio::log.trace "${FUNCNAME[0]}" "$@"
    
    free=$(df -Pm /tmp | awk 'NR==2{print $4}')
    if ((size + 7 > free)); then
        bashio::exit.nok "Error: not enough free space (${free}MB) to download update (${size}MB). Some additional space is needed to create a virtual disk."
    fi

    # The overhead of the VFAT filesystem ist about 3 MByte
    dd if=/dev/zero of="${TMP_IMG}" bs=1M count=$((size+5))  > /dev/null 2>&1
    mkfs.vfat -n CONFIG "${TMP_IMG}"
    mkdir -p "${TMP_MOUNT}"
    mount -t auto -o loop "${TMP_IMG}" "${TMP_MOUNT}"

    bashio::log "Prepared image with size: $(df -Pm "${TMP_MOUNT}" | awk 'NR==2{print $4}')M"
    
}

# download rauc bundle from url and save in image
# Arguments: $1 url
function download_image() {
    local url="$*"

    bashio::log.trace "${FUNCNAME[0]}" "$@"
    
    bashio::log "Download from ${url}"
    wget -T 20 -P "${TMP_MOUNT}" "${url}"
    if [ $? -eq 0 ]; then
        bashio::log "Download completed successfully."
    else
        umount "${TMP_MOUNT}" && rm "${TMP_IMG}"
        bashio::exit.nok "Error during Download."
    fi
}

# Unmount and make loop
function unmount_and_make_loop() {
    bashio::log.trace "${FUNCNAME[0]}" "$@"
    
    umount "${TMP_MOUNT}"
    losetup -f "${TMP_IMG}"
}

# Unmount and make loop
function preserve_authorized_keys() {
    bashio::log.trace "${FUNCNAME[0]}" "$@"

    mkdir -p /tmp/hassos-overlay
    mount /dev/disk/by-label/hassos-overlay /tmp/hassos-overlay
    cp /tmp/hassos-overlay/root/.ssh/authorized_keys "${TMP_MOUNT}"
    umount /tmp/hassos-overlay
}

############################
# Main script

if bashio::config.has_value "loglevel"; then
    LOGLEVEL=$(bashio::config "loglevel")
    bashio::log.level LOGLEVEL
    bashio::log "Log level set to '${LOGLEVEL}'"
fi

# Check if the add-on is running in protected mode
if bashio::addon.protected; then
    bashio::log.warning
    bashio::log.warning "Add-on is running in protection mode. Please disable 'Protection mode' in the 'Info' tab of this add-on."
    bashio::log.warning
    bashio::exit.ok
fi

# Get system info
BOARD=$(bashio::os.board)
OS_VERSION=$(bashio::os.version)
ADDON_VERSION=$(bashio::addon.version)

bashio::log "Current board: ${BOARD}"
bashio::log "Current OS version: ${OS_VERSION}"
bashio::log "Add-on version: ${ADDON_VERSION}"

if printf "${OS_VERSION}\n${ADDON_VERSION}\n" | sort -V -c > /dev/null 2>&1 && bashio::config.true 'upgrade_only'; then
    bashio::log.warning
    bashio::log.warning "Current OS version newer or same then add-on version. Please change add-on configuration option 'upgrade_only' to continue."
    bashio::log.warning
    bashio::exit.ok
fi

# reset configuration option to upgrade only
bashio::addon.option 'upgrade_only' true

ASSET=$(fetch_asset "${ADDON_VERSION}" "${BOARD}")
IMAGE_URL=$(get_asset_url "${ASSET}")
IMAGE_SIZE=$(get_asset_size "${ASSET}") # in Byte


create_tmp_image_and_mount $(( (IMAGE_SIZE/(1024*1024)) + 1 )) # crude round up -> add 1 MByte

download_image "${IMAGE_URL}"
bashio::config.true 'preserve_authorized_keys' && preserve_authorized_keys

unmount_and_make_loop

bashio::os.config_sync
