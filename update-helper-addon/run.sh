#!/usr/bin/with-contenv bashio

bashio::log.level "trace"

GITHUB_REPO="citrux/hassos"
RELEASES_URL="https://api.github.com/repos/${GITHUB_REPO}/releases"


# Fetch the image url from GitHub
# Arguments: $1 version, $2 board
function fetch_image_url() {
    local version=${1}
    local board=${2}
    local response
    local url

    bashio::log.trace "${FUNCNAME[0]}" "$@"
    
    response=$(curl -s -f "$RELEASES_URL")
    if [ $? -ne 0 ]; then
        bashio::log.debug "$resonse"
        bashio::exit.nok "Error fetching releases from ${RELEASES_URL}"
    fi

    # Filter for the correct one and extract download url
    url=$(echo "$response" | jq -r \
        --arg filter "${board}-${version}" \
        '.[] | .assets[] | select(.name | contains($filter) and endswith(".raucb")) | .browser_download_url')

    if [ -z "$url" ]; then
        bashio::log.debug "$url"
        bashio::exit.nok "No suitable release found for board '${board}' and version '${version}'."
        exit 1
    fi

    echo $url
}

# Install rauc bundle from url
# Arguments: $1 url
function install_image() {
    local url=$*

    bashio::log.trace "${FUNCNAME[0]}" "$@"
    
    bashio::log "Installing from ${url}"
    rauc install "$url"
    if [ $? -eq 0 ]; then
        bashio::log "Installation completed successfully."
    else
        bashio::exit.nok "Error during installation."
    fi
}


# Get user options
ALLOW_REINSTALL=$(bashio::config 'allow_reinstall')

# Get system info
BOARD=$(bashio::os.board)
OS_VERSION=$(bashio::os.version)
ADDON_VERSION=$(bashio::addon.version)

# Main script

bashio::log "Current board: $BOARD"
bashio::log "Current OS version: $OS_VERSION"
bashio::log "Addon version: $ADDON_VERSION"

if [ "$OS_VERSION" == "$ADDON_VERSION" ] && [ "$ALLOW_REINSTALL" == false ]; then
    bashio::log.notice "Already up-to-date with version $ADDON_VERSION. Change configuration option to allow reinstallation."
    bashio::exit.ok
fi

IMAGE_URL=$(fetch_image_url $ADDON_VERSION $BOARD)

install_image $IMAGE_URL

bashio::log "Rebooting now..."
bashio::host.reboot
bashio::addon.stop

