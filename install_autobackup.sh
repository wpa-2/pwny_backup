#!/bin/bash

# Define the home directory of the original user running the script (not root)
USER_HOME=$(eval echo ~$SUDO_USER)
SSH_KEY_PATH="$USER_HOME/.ssh/pwnagotchi_backup_key"
CONFIG_FILE="/etc/pwnagotchi/config.toml"
PLUGIN_DIR="/usr/local/share/pwnagotchi/custom-plugins"
AUTOBACKUP_SCRIPT="$PLUGIN_DIR/autobackup.py"
AUTOBACKUP_URL="https://github.com/wpa-2/pwny_backup/raw/main/autobackup.py"

# Ensure the script is run with sudo
if [ -z "$SUDO_USER" ]; then
    echo "Error: This script must be run with sudo."
    exit 1
fi

# Ensure SSH key file has the correct permissions
echo "Checking permissions for SSH key..."
if [ -f "$SSH_KEY_PATH" ]; then
    KEY_PERMS=$(stat -c "%a" $SSH_KEY_PATH)
    if [ "$KEY_PERMS" != "600" ]; then
        echo "Fixing permissions for $SSH_KEY_PATH..."
        chmod 600 $SSH_KEY_PATH
        if [ $? -ne 0 ]; then
            echo "Failed to set correct permissions on $SSH_KEY_PATH"
            exit 1
        fi
    fi
else
    echo "SSH key not found at $SSH_KEY_PATH."
    exit 1
fi

# Prompt for local backup path and set default if empty
read -p "Enter the local backup path (e.g., $USER_HOME/backup/): " LOCAL_BACKUP_PATH
LOCAL_BACKUP_PATH=${LOCAL_BACKUP_PATH:-"$USER_HOME/backup/"}

# Check if the local backup directory exists, if not create it
if [ ! -d "$LOCAL_BACKUP_PATH" ]; then
    echo "Local backup directory does not exist, creating $LOCAL_BACKUP_PATH..."
    mkdir -p "$LOCAL_BACKUP_PATH"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create directory $LOCAL_BACKUP_PATH"
        exit 1
    fi
fi

# Prompt to enable remote backups
read -p "Do you want to enable remote backups? (y/n): " ENABLE_REMOTE

if [[ "$ENABLE_REMOTE" == "y" || "$ENABLE_REMOTE" == "Y" ]]; then
    # Prompt for remote backup information
    read -p "Enter the remote backup information (e.g., user@remotehost:/path/to/backup): " REMOTE_BACKUP

    # Validate the remote backup format
    if [[ ! "$REMOTE_BACKUP" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+:[a-zA-Z0-9/_-]+$ ]]; then
        echo "Error: Invalid remote backup format."
        exit 1
    fi

    # Extract the remote username and host for SSH connection test
    REMOTE_USER=$(echo "$REMOTE_BACKUP" | cut -d'@' -f1)
    REMOTE_HOST=$(echo "$REMOTE_BACKUP" | cut -d'@' -f2 | cut -d':' -f1)

    # Test SSH connection to the remote server using the key
    echo "Testing SSH connection to $REMOTE_USER@$REMOTE_HOST using key $SSH_KEY_PATH..."

    sudo -u $SUDO_USER ssh -i $SSH_KEY_PATH -o BatchMode=yes -o ConnectTimeout=5 $REMOTE_USER@$REMOTE_HOST "echo SSH connection successful!" > /dev/null 2>&1

    if [ $? -eq 0 ];then
        echo "SSH connection to $REMOTE_USER@$REMOTE_HOST was successful."
    else
        echo "Error: SSH connection to $REMOTE_USER@$REMOTE_HOST failed. Please verify the SSH key and remote server details."
        exit 1
    fi
else
    REMOTE_BACKUP="user@remotehost:/path/to/backup"
    echo "Remote backups are disabled. Adding commented remote backup line."
fi

# Download the autobackup.py script
echo "Downloading autobackup.py script..."
mkdir -p $PLUGIN_DIR
wget -O $AUTOBACKUP_SCRIPT $AUTOBACKUP_URL || { echo "Error: Failed to download autobackup.py"; exit 1; }

# Set the correct permissions for the script
chmod +x $AUTOBACKUP_SCRIPT
echo "autobackup.py installed to $PLUGIN_DIR."

# Remove existing autobackup configuration to avoid duplicates
sudo sed -i "/main.plugins.autobackup.remote_backup/d" $CONFIG_FILE

# Check if configuration already exists and append only if necessary
if ! grep -q "main.plugins.autobackup.enabled" $CONFIG_FILE; then
    echo "Updating $CONFIG_FILE with autobackup configuration..."

    sudo bash -c "cat <<EOL >> $CONFIG_FILE

# Autobackup Plugin Configuration
main.plugins.autobackup.enabled = true
main.plugins.autobackup.interval = 1  # Backup every 1 hour
main.plugins.autobackup.max_tries = 3
main.plugins.autobackup.local_backup_path = \"$LOCAL_BACKUP_PATH\"
EOL"

    # Add remote backup details (either commented or active based on selection)
    if [[ "$ENABLE_REMOTE" == "y" || "$ENABLE_REMOTE" == "Y" ]]; then
        sudo bash -c "cat <<EOL >> $CONFIG_FILE
main.plugins.autobackup.remote_backup = \"$REMOTE_BACKUP,$SSH_KEY_PATH\"
EOL"
    else
        sudo bash -c "cat <<EOL >> $CONFIG_FILE
# main.plugins.autobackup.remote_backup = \"$REMOTE_BACKUP,$SSH_KEY_PATH\"
EOL"
    fi
else
    echo "Autobackup configuration already exists in $CONFIG_FILE."
fi

# Finished
echo "Configuration update complete."
