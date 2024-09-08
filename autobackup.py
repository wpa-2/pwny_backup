import pwnagotchi.plugins as plugins
from pwnagotchi.utils import StatusFile
import logging
import os
import subprocess
import platform
import socket
from datetime import datetime
import threading
import time

class autobackup(plugins.Plugin):
    __author__ = 'Your Name'
    __version__ = '2.1.0'
    __license__ = 'GPL3'
    __description__ = 'This plugin backs up files using the hostname for the backup filename and supports local and remote backups using rsync.'

    def __init__(self):
        self.ready = False
        self.tries = 0
        self.status = StatusFile('/root/.auto-backup')

    def on_loaded(self):
        logging.info(f"AUTO-BACKUP: Full loaded configuration: {self.options}")

        # Required options (local backup path and interval)
        required_options = ['interval', 'local_backup_path']
        for opt in required_options:
            if opt not in self.options or not self.options[opt]:
                logging.error(f"AUTO-BACKUP: Option {opt} is not set.")
                return

        # Remote backup is optional, check if it's set
        if 'remote_backup' in self.options and self.options['remote_backup']:
            logging.info("AUTO_BACKUP: Remote backup is configured.")
        else:
            logging.info("AUTO_BACKUP: Remote backup is not configured. Only local backups will be performed.")

        # Start the time-based backup thread
        backup_interval = self.options.get('interval', 1) * 3600  # Default to 1 hour if not set
        self.backup_thread = threading.Thread(target=self.schedule_backup, args=(backup_interval,), daemon=True)
        self.backup_thread.start()
        logging.info("AUTO_BACKUP: Backup scheduler started")

    def on_manual_mode(self, agent):
        logging.info("AUTO_BACKUP: Pwnagotchi has entered manual mode. Starting backup.")
        self.perform_backup()

    def on_command(self, agent, name, message):
        if name == 'bpwny':
            logging.info("AUTO_BACKUP: bpwny command received. Starting backup.")
            self.perform_backup()
            return "Backup initiated."

    def schedule_backup(self, interval):
        while True:
            logging.info(f"AUTO_BACKUP: Scheduled time-based backup after {interval / 3600} hours.")
            self.perform_backup()
            time.sleep(interval)

    def perform_backup(self):
        """Perform the backup process based on the system's architecture."""

        # Detect 32-bit or 64-bit OS
        os_arch = platform.machine()
        if os_arch == "aarch64":
            # 64-bit OS
            files_to_backup = [
                "/root/brain.json",
                "/root/.api-report.json",
                "/root/handshakes/",
                "/root/peers/",
                "/etc/pwnagotchi/",
                "/boot/firmware/config.txt",
                "/boot/firmware/cmdline.txt",
                "/usr/local/share/pwnagotchi/custom-plugins/"
            ]
        elif os_arch == "armv7l":
            # 32-bit OS
            files_to_backup = [
                "/root/brain.json",
                "/root/.api-report.json",
                "/root/handshakes/",
                "/root/peers/",
                "/etc/pwnagotchi/",
                "/boot/config.txt",
                "/boot/cmdline.txt",
                "/usr/local/share/pwnagotchi/custom-plugins/"
            ]
        else:
            logging.error("AUTO_BACKUP: Unsupported architecture detected.")
            return

        # Ensure the local backup directory exists
        if not os.path.exists(self.options['local_backup_path']):
            logging.info(f"AUTO_BACKUP: Local backup path does not exist. Creating: {self.options['local_backup_path']}")
            os.makedirs(self.options['local_backup_path'], exist_ok=True)

        # Get the hostname and create the backup filename
        hostname = socket.gethostname()
        backup_filename = f"{hostname}-backup.tar.gz"

        # Check if the files exist
        valid_files = [f for f in files_to_backup if os.path.exists(f)]
        if not valid_files:
            logging.info("AUTO_BACKUP: No valid files to backup, skipping.")
            return

        try:
            logging.info("AUTO_BACKUP: Backing up ...")
            local_backup_path = os.path.join(self.options['local_backup_path'], backup_filename)
            
            # Exclude log files from the backup
            tar_command = f"tar --exclude='/etc/pwnagotchi/log/pwnagotchi.log' -czvf {local_backup_path} {' '.join(valid_files)}"
            logging.info(f"AUTO_BACKUP: Running tar command: {tar_command}")
            
            result = subprocess.run(tar_command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if result.returncode != 0:
                logging.error(f"AUTO_BACKUP: Failed to create backup. Error: {result.stderr.decode()}")
                return

            logging.info(f"AUTO_BACKUP: Backup created successfully at {local_backup_path}")

            # Check if remote backup is configured and not empty
            if 'remote_backup' in self.options and self.options['remote_backup']:
                try:
                    # Extract the server and SSH key from the combined remote_backup option
                    server_address, ssh_key = self.options['remote_backup'].split(',')
                    rsync_command = f"rsync -avz -e 'ssh -i {ssh_key} -o StrictHostKeyChecking=no' {local_backup_path} {server_address}/"
                    logging.info(f"AUTO_BACKUP: Sending backup to server using rsync: {rsync_command}")
                    result = subprocess.run(rsync_command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                    if result.returncode == 0:
                        logging.info("AUTO_BACKUP: Backup successfully sent to server using rsync.")
                    else:
                        logging.error(f"AUTO_BACKUP: Failed to send backup to server using rsync. Error: {result.stderr.decode()}")
                except subprocess.CalledProcessError as e:
                    logging.error(f"AUTO_BACKUP: Failed to send backup to server using rsync. Error: {e}")
        except OSError as os_e:
            self.tries += 1
            logging.error(f"AUTO_BACKUP: Error: {os_e}")

