# Pwnagotchi AutoBackup Plugin

This plugin allows you to automatically back up important files on your Pwnagotchi device. It supports both local and remote backups via rsync over SSH.

## Features
- **Automatic Backups:** Periodically backs up files to a local or remote server.
- **Local and Remote Backup:** Specify a local directory and a remote SSH server to store backups.
- **Architecture-Aware:** Detects whether your system is 32-bit or 64-bit and adjusts the backup files accordingly.

## Requirements
- **Pwnagotchi:** Installed on a Raspberry Pi.
- **SSH Key:** Required for remote backups.
- **Internet Access:** To download the plugin and perform remote backups.

## Installation

### Step 1: Create an SSH Key
To perform remote backups, you’ll need to create an SSH key that the Pwnagotchi can use to connect to the remote server.

1. Generate the SSH key (on your Pwnagotchi):
   `ssh-keygen -t rsa -b 4096 -f ~/.ssh/pwnagotchi_backup_key -N ""`

2. Copy the SSH public key to your remote server:
   `ssh-copy-id -i ~/.ssh/pwnagotchi_backup_key.pub user@remotehost`  
   Replace `user@remotehost` with your remote server's username and IP address.

### Step 2: Set Up SSH Key for GitHub
Add the SSH key (`~/.ssh/pwnagotchi_backup_key.pub`) to your GitHub account under Settings > SSH and GPG keys.

Then
`nano ~/.ssh/config`

```
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/pwnagotchi_backup_key
```

And finally run these commands

```
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/pwnagotchi_backup_key
ssh -T git@github.com
```

Result should be 
`Hi USERNAME! You've successfully authenticated, but GitHub does not provide shell access.`




Use the following command to display the key:  
`cat ~/.ssh/pwnagotchi_backup_key.pub`  
Make sure to copy the output to your clipboard.

### Step 3: Create a Private GitHub Repository
1. Go to GitHub and log in to your account.
2. Click the + icon in the upper right corner and select **New repository**.
3. Enter a repository name (e.g., **Backup**).
4. Select **Private** to keep your repository secure.
5. Click **Create repository**.

### Step 4: Install the AutoBackup Plugin
Download the installation script to your Pwnagotchi:  
`wget https://github.com/wpa-2/pwny_backup/raw/main/install_autobackup.sh -O install_autobackup.sh`  

Make the script executable:  
`chmod +x install_autobackup.sh`  

Run the installation script:  
`sudo ./install_autobackup.sh`  

The script will:
- Check the permissions of your SSH key.
- Prompt for the local and remote backup paths.
- Test your SSH connection to the remote server.
- Download the `autobackup.py` plugin and install it.
- Update the Pwnagotchi configuration file with the required plugin configuration.

### Step 5: Configure the Plugin
During the installation, you'll be prompted to enter:
- **Local Backup Path:** Directory on the Pwnagotchi where local backups will be stored.
- **Remote Backup:** The SSH connection string for the remote server (e.g., `user@remotehost:/path/to/backup`).

### Example configuration in `config.toml`:

Autobackup Plugin Configuration
```
main.plugins.autobackup.github_repo = "git@github.com:username/repository.git"
main.plugins.autobackup.github_backup_dir = "Backups"
main.plugins.autobackup.remote_backup = "user@LOCALIP:/path/to/folder/,/home/pi/.ssh/pwnagotchi_backup_key"
main.plugins.autobackup.enabled = true
main.plugins.autobackup.interval = 1  # Backup every 1 hour
main.plugins.autobackup.max_tries = 3
main.plugins.autobackup.local_backup_path = "/home/pi/backup/"`
```

### Step 6: Verify Installation
Restart Pwnagotchi to apply the changes:  
`sudo systemctl restart pwnagotchi`  

Check the logs to verify the plugin is running:  
`pwnlog`  
You should see log entries indicating that the backup process is scheduled and running.

## Backup Frequency
The backup interval is set in the configuration file. Adjust it based on your needs; for example, a 1-hour interval might be suitable for regular backups, while longer intervals may suffice for less critical data.

## Security Considerations
Ensure your SSH keys are kept secure. Do not share your private key, and consider using passphrases for added security.

## Contact/Support Information
If you encounter issues, please open an issue on the [GitHub repository](https://github.com/wpa-2/pwny_backup/issues).

## Changelog
- **Version x.0:** Initial release.

## Troubleshooting
- **SSH Connection Issues:** Ensure that the SSH key has been properly configured and that the Pwnagotchi can connect to the remote server without needing a password:
   `ssh -i /home/pi/.ssh/pwnagotchi_backup_key user@remotehost`  
   `ssh -T git@github.com`

- **Permissions:** Ensure the SSH key file has the correct permissions:
```
chmod 700 ~/.ssh
chmod 600 ~/.ssh/pwnagotchi_backup_key
chmod 644 ~/.ssh/pwnagotchi_backup_key.pub
```

- **Logs:** Check the Pwnagotchi logs for any errors or issues with the backup process:  
   `pwnlog`

  ## Known issues
  
Some times this shows as an error (not really an issue if your using pwny a lot and its not sat in manu mode)

`14:21:43 [ERROR] AUTO_BACKUP: Git command 'cd /home/pi/backup/Backups && git commit -m 'Backup on 2024-09-21 14:21:43.157731'' failed with exit code 1`

Just means the backup hasnt changed and theres nothing new to upload, i need to fix that at some point. 
 



