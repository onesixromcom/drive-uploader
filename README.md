# Google Driver file uploader/updater

## Overview

This tiny script was created to simplify uploading/updating same files on Google Drive automatically. 

For example this could be useful to make a backups of password files for KeepassX to the Drive.

Using this script with cron will automate your backup process to own Google Drive.

## Requirements

````
sudo apt install curl
````

#### Steps to make it work:

1. Create a new project in the Google Cloud Console.
1. Enable the Google Drive API for your project.
1. Create credentials for your project to enable OAuth 2.0 authentication.
1. Use the OAuth 2.0 flow to obtain an access token. (Desktop app)

After there steps you should have client_id and client_secret credentials. Copy client.var to .client and paste credentials there.

Run ./drive-upload.sh script. It will ask you to visit url, where you will give permissins from your user to acceess the Drive folder. On the last page you will receive Client Code which should be inserted in .client file.

Create files.txt file with full path to files you want to upload to Driver. By default files will be uploaded in "backup" folder. You should create it before running the script.

After all those steps you should be able to upload listed files to backup folder on Google Drive. Access_token will be created on first run. After access token will be expired it will be regenerated with refresh token. All variables (tokens, folder id, files ids) are located in ./vars folder.

### Known bugs:

1. Script is not working when more than 1 file was found on Drive. This could be related to files that present in Trash with the same name. You should clear Trash first.
