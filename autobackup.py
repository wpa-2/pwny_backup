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
import shutil

class autobackup(plugins.Plugin):
    __author__ = 'WPA2'
    __version__ = '2.1.0'
    __license__ = 'GPL3'
    __description__ = 'This plugin backs up files using the hostname for the backup filename and supports local and remote backups using rsync.'

    def __init__(self):
        self.ready = False
        self.tries = 0
        self.status = StatusFile('/root/.auto-backup')

    def on_loaded(self):
        logging.info(f"AUTO-BACKUP: Full loaded configuration: {self.options}")

        required_options = ['interval', 'local_backup_path']
        for opt in required_options:
            if opt not in self.options:
                logging.error(f"AUTO-BACKUP: Required option {opt} is not set.")
                return

        backup_interval = self.options.get('interval', 1) * 3600
        self.backup_thread = threading.Thread(target=self.schedule_backup, args=(backup_interval,), daemon=True)
        self.backup_thread.start()
        logging.info("AUTO_BACKUP: Backup scheduler started")

    def schedule_backup(self, interval):
        while True:
            logging.info(f"AUTO_BACKUP: Scheduled time-based backup after {interval / 3600} hours.")
            self.perform_backup()
            time.sleep(interval)

    def perform_backup(self):
        os_arch = platform.machine()
        files_to_backup = self.get_files_to_backup(os_arch)

        if not os.path.exists(self.options['local_backup_path']):
            logging.info(f"AUTO_BACKUP: Local backup path does not exist. Creating: {self.options['local_backup_path']}")
            os.makedirs(self.options['local_backup_path'], exist_ok=True)

        hostname = socket.gethostname()
        backup_filename = f"{hostname}-backup.tar.gz"
        local_backup_path = os.path.join(self.options['local_backup_path'], backup_filename)

        valid_files = [f for f in files_to_backup if os.path.exists(f)]
        if not valid_files:
            logging.info("AUTO_BACKUP: No valid files to backup, skipping.")
            return

        try:
            self.create_backup_archive(valid_files, local_backup_path)
            self.handle_github_backup(local_backup_path, backup_filename)
            self.handle_remote_backup(local_backup_path, backup_filename)

        except OSError as os_e:
            self.tries += 1
            logging.error(f"AUTO_BACKUP: Error: {os_e}")

    def get_files_to_backup(self, os_arch):
        if os_arch == "aarch64":
            return [
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
            return [
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
            return []

    def create_backup_archive(self, valid_files, local_backup_path):
        logging.info("AUTO_BACKUP: Backing up ...")
        tar_command = f"tar --exclude='/etc/pwnagotchi/log/pwnagotchi.log' -czvf {local_backup_path} {' '.join(valid_files)}"
        logging.info(f"AUTO_BACKUP: Running tar command: {tar_command}")

        result = subprocess.run(tar_command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if result.returncode != 0:
            logging.error(f"AUTO_BACKUP: Failed to create backup. Error: {result.stderr.decode()} Command: {tar_command}")
            return

        logging.info(f"AUTO_BACKUP: Backup created successfully at {local_backup_path}")

    def handle_github_backup(self, local_backup_path, backup_filename):
        if 'github_repo' in self.options and 'github_backup_dir' in self.options:
            github_backup_dir = self.options['github_backup_dir']
            github_backup_path = os.path.join(self.options['local_backup_path'], github_backup_dir)

            if not os.path.exists(github_backup_path):
                os.makedirs(github_backup_path)

            final_backup_path = os.path.join(github_backup_path, backup_filename)
            shutil.copy(local_backup_path, final_backup_path)
            self.git_setup(github_backup_path, backup_filename)

    def git_setup(self, github_backup_path, backup_filename):
        os.makedirs(os.path.join(github_backup_path, '.git', 'info'), exist_ok=True)
        sparse_checkout_path = os.path.join(github_backup_path, '.git', 'info', 'sparse-checkout')
        backup_dir = self.options.get('github_backup_dir', 'Backups')
        
        with open(sparse_checkout_path, 'w') as sparse_file:
            sparse_file.write(f"{backup_dir}/*\n")
        
        logging.info(f"AUTO_BACKUP: Sparse checkout set for {backup_dir}/*")

        subprocess.run(f"git config core.sparseCheckout true", cwd=github_backup_path, shell=True)
        result = subprocess.run(f"git read-tree -mu HEAD", cwd=github_backup_path, shell=True)
        if result.returncode != 0:
            logging.error(f"AUTO_BACKUP: Failed to execute read-tree. Error: {result.stderr.decode()}")

        self.run_git_commands(github_backup_path, backup_filename)

    def run_git_commands(self, github_backup_path, backup_filename):
        git_commands = [
            f"cd {github_backup_path} && git add -f {backup_filename}",
            f"cd {github_backup_path} && git commit -m 'Backup on {datetime.now()}'",
            f"cd {github_backup_path} && git push --force origin main"
        ]

        for cmd in git_commands:
            logging.info(f"AUTO_BACKUP: Running Git command: {cmd}")
            result = subprocess.run(f"sudo -u pi bash -c \"{cmd}\"", shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if result.returncode != 0:
                logging.error(f"AUTO_BACKUP: Git command '{cmd}' failed with exit code {result.returncode}")
                return

    def handle_remote_backup(self, local_backup_path, backup_filename):
        if 'remote_backup' in self.options:
            try:
                remote_config = self.options['remote_backup']
                if ',' not in remote_config:
                    raise ValueError("Remote backup configuration must be in the format 'user@host:/path,key_path'")

                server_address, ssh_key = remote_config.split(',')
                rsync_command = f"rsync -avz -e 'ssh -i {ssh_key} -o StrictHostKeyChecking=no' {local_backup_path} {server_address}/"
                logging.info(f"AUTO_BACKUP: Sending backup to server using rsync: {rsync_command}")
                result = subprocess.run(rsync_command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                if result.returncode == 0:
                    logging.info("AUTO_BACKUP: Backup successfully sent to server using rsync.")
                else:
                    logging.error(f"AUTO_BACKUP: Failed to send backup to server using rsync. Error: {result.stderr.decode()}")
            except ValueError as e:
                logging.error(f"AUTO_BACKUP: Incorrect remote backup configuration format. {str(e)}")

