# **Pwnagotchi AutoBackup Plugin**

This plugin allows you to automatically back up important files on your Pwnagotchi device. It supports both local and remote backups via `rsync` over SSH.

## **Features**

- **Automatic Backups**: Periodically backs up files to a local or remote server.
- **Local and Remote Backup**: Specify a local directory and a remote SSH server to store backups.
- **Architecture-Aware**: Detects whether your system is 32-bit or 64-bit and adjusts the backup files accordingly.

## **Requirements**

- **Pwnagotchi**: Installed on a Raspberry Pi.
- **SSH Key**: Required for remote backups.
- **Internet Access**: To download the plugin and perform remote backups.

## **Installation**

### **Step 1: Create an SSH Key**

To perform remote backups, you’ll need to create an SSH key that the Pwnagotchi can use to connect to the remote server.

- Generate the SSH key (on your Pwnagotchi):

  ```bash
  ssh-keygen -t rsa -b 4096 -f ~/.ssh/pwnagotchi_backup_key -N ""
  ```

- Copy the SSH public key to your remote server:

  ```bash
  ssh-copy-id -i ~/.ssh/pwnagotchi_backup_key user@remotehost
  ```

  Replace `user@remotehost` with your remote server's username and IP address.

### **Step 2: Install the AutoBackup Plugin**

- Download the installation script to your Pwnagotchi:

  ```bash
  wget https://github.com/wpa-2/pwny_backup/raw/main/install_autobackup.sh -O install_autobackup.sh
  ```

- Make the script executable:

  ```bash
  chmod +x install_autobackup.sh
  ```

- Run the installation script:

  ```bash
  sudo ./install_autobackup.sh
  ```

The script will:

- Check the permissions of your SSH key.
- Prompt for the local and remote backup paths.
- Test your SSH connection to the remote server.
- Download the `autobackup.py` plugin and install it.
- Update the Pwnagotchi `config.toml` file with the required plugin configuration.

### **Step 3: Configure the Plugin**

During the installation, you'll be prompted to enter:

- **Local Backup Path**: Directory on the Pwnagotchi where local backups will be stored.
- **Remote Backup**: The SSH connection string for the remote server (e.g., `user@remotehost:/path/to/backup`).

These details will be added to the Pwnagotchi configuration file (`/etc/pwnagotchi/config.toml`).

Example configuration:

```toml
# Autobackup Plugin Configuration
main.plugins.autobackup.enabled = true
main.plugins.autobackup.interval = 1  # Backup every 1 hour
main.plugins.autobackup.max_tries = 3
main.plugins.autobackup.local_backup_path = \"$LOCAL_BACKUP_PATH\"
main.plugins.autobackup.remote_backup = \"$REMOTE_BACKUP,$SSH_KEY_PATH\"
```

### **Step 4: Verify Installation**

- Restart Pwnagotchi to apply the changes:

  ```bash
  sudo systemctl restart pwnagotchi
  ```

- Check the logs to verify the plugin is running:

  ```bash
  tail -f /var/log/pwnagotchi.log
  ```

  You should see log entries indicating that the backup process is scheduled and running.

## **Troubleshooting**

- **SSH Connection Issues**: Ensure that the SSH key has been properly configured and that the Pwnagotchi can connect to the remote server without needing a password.

  ```bash
  ssh -i /home/pi/.ssh/pwnagotchi_backup_key user@remotehost
  ```

- **Permissions**: Ensure the SSH key file has the correct permissions:

  ```bash
  chmod 600 /home/pi/.ssh/pwnagotchi_backup_key
  ```

- **Logs**: Check the Pwnagotchi logs for any errors or issues with the backup process:

  ```bash
  pwnlog
  ```


