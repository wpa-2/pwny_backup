#!/bin/bash

# Define the home directory of the original user running the script (not root)
USER_HOME=$(eval echo ~$SUDO_USER)
SSH_KEY_PATH="$USER_HOME/.ssh/pwnagotchi_backup_key"
CONFIG_FILE="/etc/pwnagotchi/config.toml"
PLUGIN_DIR="/usr/local/share/pwnagotchi/custom-plugins"
AUTOBACKUP_SCRIPT="$PLUGIN_DIR/autobackup.py"
AUTOBACKUP_URL="https://raw.githubusercontent.com/wpa-2/pwny_backup/refs/heads/Testing/autobackup.py"

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
    read -p "SSH key not found. Would you like to generate a new SSH key? (y/n): " GEN_KEY
    if [[ "$GEN_KEY" == "y" || "$GEN_KEY" == "Y" ]]; then
        # Generate a new SSH key
        ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N ""
        echo "New SSH key generated."
    else
        echo "SSH key is required for GitHub backups. Exiting."
        exit 1
    fi
fi

# Output the public SSH key and wait for user to add it to GitHub
echo "Please add the following public SSH key to your GitHub account:"
cat "$SSH_KEY_PATH.pub"
echo ""
echo "Go to https://github.com/settings/keys to add this key."
echo "After adding the key, press Enter to continue."

# Pause and wait for user confirmation
read -p "Press Enter to continue after adding the key to GitHub."

# Test GitHub SSH connection
echo "Testing SSH connection to GitHub..."
sudo -u $SUDO_USER ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"
if [ $? -ne 0 ]; then
    echo "Error: Failed to authenticate with GitHub using the SSH key."
    echo "Please ensure your SSH key has been added to GitHub and try again."
    exit 1
else
    echo "GitHub authentication successful!"
fi

# Prompt for local backup path and set default if empty
read -p "Enter the local backup path (e.g., /home/pi/backup/): " LOCAL_BACKUP_PATH
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

# Fix ownership of the backup directory
echo "Fixing ownership of the local backup directory..."
sudo chown -R $SUDO_USER:$SUDO_USER "$LOCAL_BACKUP_PATH"
sudo chmod -R 755 "$LOCAL_BACKUP_PATH"

# Prompt for GitHub repository
read -p "Would you like to set up GitHub backups? (y/n): " ENABLE_GITHUB

if [[ "$ENABLE_GITHUB" == "y" || "$ENABLE_GITHUB" == "Y" ]]; then
    read -p "Enter the GitHub repository URL (e.g., git@github.com:username/repository.git): " GITHUB_REPO
    read -p "Enter the GitHub backup directory (default: Backups): " GITHUB_BACKUP_DIR
    GITHUB_BACKUP_DIR=${GITHUB_BACKUP_DIR:-"Backups"}

    # Get the device hostname for branch name
    HOSTNAME=$(hostname)
    read -p "Enter the GitHub branch name for this device (default: $HOSTNAME): " GITHUB_BRANCH
    GITHUB_BRANCH=${GITHUB_BRANCH:-"$HOSTNAME"}

    # Clone the GitHub repository if it doesn't already exist
    if [ ! -d "$LOCAL_BACKUP_PATH/.git" ]; then
        echo "Cloning GitHub repository into $LOCAL_BACKUP_PATH..."
        sudo -u $SUDO_USER git clone $GITHUB_REPO "$LOCAL_BACKUP_PATH"
        cd $LOCAL_BACKUP_PATH
        sudo -u $SUDO_USER git checkout -b $GITHUB_BRANCH || sudo -u $SUDO_USER git checkout $GITHUB_BRANCH
    fi

    # Mark the repository as safe for Git
    sudo -u $SUDO_USER git config --global --add safe.directory $LOCAL_BACKUP_PATH

    # Prompt for Git user details
    read -p "Enter your Git user name: " GIT_USER_NAME
    read -p "Enter your Git user email: " GIT_USER_EMAIL

    # Set Git user details for the repository
    sudo -u $SUDO_USER bash -c "cd $LOCAL_BACKUP_PATH && git config user.name '$GIT_USER_NAME' && git config user.email '$GIT_USER_EMAIL'"

    # Configure sparse checkout for files containing the hostname
    echo "Configuring sparse checkout for files with the hostname '$HOSTNAME'..."
    sudo -u $SUDO_USER bash -c "cd $LOCAL_BACKUP_PATH && git config core.sparseCheckout true && echo '$GITHUB_BACKUP_DIR/$HOSTNAME-backup.tar.gz' > .git/info/sparse-checkout"

    # Pull only the hostname-related files from the repository
    sudo -u $SUDO_USER bash -c "cd $LOCAL_BACKUP_PATH && git read-tree -mu HEAD"

    # Update the configuration file for GitHub backups
    echo "Configuring GitHub backup in Pwnagotchi settings..."
    sudo sed -i "/main.plugins.autobackup.github_repo/d" $CONFIG_FILE
    sudo sed -i "/main.plugins.autobackup.github_backup_dir/d" $CONFIG_FILE
    sudo sed -i "/main.plugins.autobackup.github_branch/d" $CONFIG_FILE
    sudo sed -i "/main.plugins.autobackup.github_ssh_key/d" $CONFIG_FILE

    sudo bash -c "cat <<EOL >> $CONFIG_FILE
main.plugins.autobackup.github_repo = \"$GITHUB_REPO\"
main.plugins.autobackup.github_backup_dir = \"$GITHUB_BACKUP_DIR\"
main.plugins.autobackup.github_branch = \"$GITHUB_BRANCH\"
main.plugins.autobackup.github_ssh_key = \"$SSH_KEY_PATH\"
EOL"
fi

# Prompt for remote backup configuration
read -p "Would you like to set up remote backups? (y/n): " ENABLE_REMOTE
if [[ "$ENABLE_REMOTE" == "y" || "$ENABLE_REMOTE" == "Y" ]]; then
    read -p "Enter the remote server address (e.g., user@hostname:/path/to/backup/): " REMOTE_SERVER
    read -p "Enter the SSH key path for remote access (default: $SSH_KEY_PATH): " SSH_KEY
    SSH_KEY=${SSH_KEY:-"$SSH_KEY_PATH"}

    # Test SSH connection to remote server
    echo "Testing SSH connection to remote server..."
    ssh -i $SSH_KEY -o BatchMode=yes $REMOTE_SERVER "exit" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "Warning: SSH key authentication to the remote server failed. You can configure it later."
    else
        echo "SSH connection to the remote server was successful!"
    fi

    # Update the configuration file for remote backups (continue even if the connection test fails)
    echo "Configuring remote backup in Pwnagotchi settings..."
    sudo sed -i "/main.plugins.autobackup.remote_backup/d" $CONFIG_FILE
    sudo bash -c "echo 'main.plugins.autobackup.remote_backup = \"$REMOTE_SERVER,$SSH_KEY\"' >> $CONFIG_FILE"
fi

# Download the autobackup.py script
echo "Downloading autobackup.py script..."
mkdir -p $PLUGIN_DIR
wget -O $AUTOBACKUP_SCRIPT $AUTOBACKUP_URL || { echo "Error: Failed to download autobackup.py"; exit 1; }

# Set the correct permissions for the script
chmod +x $AUTOBACKUP_SCRIPT
echo "autobackup.py installed to $PLUGIN_DIR."

# Remove existing autobackup configuration to avoid duplicates
sudo sed -i "/main.plugins.autobackup.local_backup_path/d" $CONFIG_FILE
sudo sed -i "/main.plugins.autobackup.interval/d" $CONFIG_FILE

# Append local backup configuration
echo "Updating Pwnagotchi configuration..."
sudo bash -c "cat <<EOL >> $CONFIG_FILE
main.plugins.autobackup.enabled = true
main.plugins.autobackup.interval = 1  # Backup every 1 hour
main.plugins.autobackup.max_tries = 3
main.plugins.autobackup.local_backup_path = \"$LOCAL_BACKUP_PATH\"
EOL"

# Finished
echo "Configuration update complete."
echo "Autobackup plugin installed and configured. You can now restart Pwnagotchi to apply changes."
