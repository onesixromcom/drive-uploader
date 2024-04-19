#!/bin/bash

DIR_VARS="./vars"
FILE_ACCESS_TOKEN="$DIR_VARS/.access_token"
FILE_REFRESH_TOKEN="$DIR_VARS/.refresh_token"
FILE_FOLDER_ID="$DIR_VARS/.folder_id"

FILE_LIST="files.txt"
FILE_CLIENT=".client"

ROOTDIR="root"
	
if ! test -f "$FILE_CLIENT"; then
   echo "Error. Access client vars file $FILE_CLIENT not found."
   exit;
fi

if ! test -f "$FILE_LIST"; then
   echo "Error. File list $FILE_LIST not found. Please create and add files to backup per line."
   exit;
fi

# Load client credentials
. "$FILE_CLIENT"

ACCESS_TOKEN=""
# 0 - is ok
# 1 - no file
# 2 - token needs to be refreshed
# 3 - invalid token
ACCESS_TOKEN_STATUS=0

# 0 - is ok
# 1 - no file
# 2 - token invalid. All chain need to be regenrated
REFRESH_TOKEN_STATUS=0

FOLDER_NAME="backup"
FOLDER_ID=""

FILE_ID=""
SLUG=""

# check if request goes in loop
RETRIES=0

function jsonValue() {
	KEY=$1
	num=$2
	awk -F"[,:}][^://]" '{for(i=1;i<=NF;i++){if($i~/\042'$KEY'\042/){print $(i+1)}}}' | tr -d '"' | sed -n ${num}p | sed -e 's/[}]*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[,]*$//'
}

function url_encode() {
    echo "$@" \
    | sed \
        -e 's/%/%25/g' \
        -e 's/ /%20/g' \
        -e 's/!/%21/g' \
        -e 's/"/%22/g' \
        -e "s/'/%27/g" \
        -e 's/#/%23/g' \
        -e 's/(/%28/g' \
        -e 's/)/%29/g' \
        -e 's/+/%2b/g' \
        -e 's/,/%2c/g' \
        -e 's/-/%2d/g' \
        -e 's/:/%3a/g' \
        -e 's/;/%3b/g' \
        -e 's/?/%3f/g' \
        -e 's/@/%40/g' \
        -e 's/\$/%24/g' \
        -e 's/\&/%26/g' \
        -e 's/\*/%2a/g' \
        -e 's/\./%2e/g' \
        -e 's/\//%2f/g' \
        -e 's/\[/%5b/g' \
        -e 's/\\/%5c/g' \
        -e 's/\]/%5d/g' \
        -e 's/\^/%5e/g' \
        -e 's/_/%5f/g' \
        -e 's/`/%60/g' \
        -e 's/{/%7b/g' \
        -e 's/|/%7c/g' \
        -e 's/}/%7d/g' \
        -e 's/~/%7e/g'
}

function search_folder_id() {
	echo "Searching for $FOLDER_NAME Folder ID."
	QUERY="mimeType='application/vnd.google-apps.folder' and title='$FOLDER_NAME'"
    #QUERY=$(echo $QUERY | sed -f url_escape.sed)
    QUERY=$(url_encode $QUERY)

    SEARCH_RESPONSE=`/usr/bin/curl \
                    --silent \
                    -X GET \
                    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
                     "https://www.googleapis.com/drive/v2/files/${ROOTDIR}/children?orderBy=title&q=${QUERY}&fields=items%2Fid"`
	# echo $SEARCH_RESPONSE
    FOLDER_ID=`echo $SEARCH_RESPONSE | jsonValue id`
    if [ -z "$FOLDER_ID" ]; then
		echo "Folder ID not found. Exit."
		exit
	else
		echo "Folder ID found. $FOLDER_ID"
		echo $FOLDER_ID > $FILE_FOLDER_ID
	fi
}

# todo: it finds items in trash which is not good.
function search_file_id() {
	echo "Searching for $SLUG File ID."
	
	QUERY="title='$SLUG'"
    #QUERY=$(echo $QUERY | sed -f url_escape.sed)
	QUERY=$(url_encode $QUERY)

    SEARCH_RESPONSE=`/usr/bin/curl \
                    --silent \
                    -X GET \
                    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
                     "https://www.googleapis.com/drive/v2/files/${FOLDER_ID}/children?orderBy=title&q=${QUERY}&fields=items%2Fid"`
	#echo $SEARCH_RESPONSE
    FILE_ID=`echo $SEARCH_RESPONSE | jsonValue id`
    #ERROR=`echo $SEARCH_RESPONSE | jsonValue code`
    #if [ -z "$ERROR" ]; then
#		echo "FATAL ERROR. exit"
		#exit
    #fi
    
    if [ -z "$FILE_ID" ]; then
		echo "File ID not found. New file will be created."
	else
		echo "File ID found. $FILE_ID"
		echo $FILE_ID > $FILE_FILE_ID
	fi
}

function get_token_status() {
	if [ -z "$ACCESS_TOKEN" ]; then
      echo "Error. Access token for token check not found."
      return;
	fi
	
	echo "Get token status"
	token_response=`/usr/bin/curl "https://www.googleapis.com/oauth2/v1/tokeninfo?access_token=${ACCESS_TOKEN}"`
	#echo "Token status response: $token_response"
	status=`echo $token_response | jsonValue error`
	echo "status=$status"
	if [ ! -z "$status" ]; then
		if [ "$status" = "invalid_token" ]; then
			ACCESS_TOKEN_STATUS=2
			return;
		fi
		if [ "$status" = "invalid_grant" ]; then
			ACCESS_TOKEN_STATUS=3
			return;
		fi
    fi
}

function get_jwt_token() {
	if [ -z "$CLIENT_CODE" ]; then
      echo "Error. Code not found."
      exit;
	fi
	
	echo "Get new tokens."
	
	access_token_response=`/usr/bin/curl \
		--request POST \
		-H "Content-Type: application/x-www-form-urlencoded" \
		--data "code=${CLIENT_CODE}&client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}&redirect_uri=urn:ietf:wg:oauth:2.0:oob&grant_type=authorization_code" \
		https://accounts.google.com/o/oauth2/token`

	#echo "resp=$access_token_response"
	status=`echo $access_token_response | jsonValue error`
	echo "status=$status"
	if [ ! -z "$status" ]; then
		if [ "$status" = "invalid_grant" ]; then
			client_code_message
		fi
    fi
	
	ACCESS_TOKEN=`echo $access_token_response | jsonValue access_token`
	if [ ! -z "$ACCESS_TOKEN" ]; then
		if test -f "$FILE_ACCESS_TOKEN"; then rm $FILE_ACCESS_TOKEN ;fi
		echo $ACCESS_TOKEN > $FILE_ACCESS_TOKEN
	else
		echo "Access token not found."
	fi
	
	REFRESH_TOKEN=`echo $access_token_response | jsonValue refresh_token`
	if [ ! -z "$REFRESH_TOKEN" ]; then
		if test -f "$FILE_REFRESH_TOKEN"; then rm $FILE_REFRESH_TOKEN ;fi
		echo $REFRESH_TOKEN > $FILE_REFRESH_TOKEN
	else
		echo "Refresh token not found."
	fi
	
	return
}

function refresh_access_token() {
	if ! test -f "$FILE_REFRESH_TOKEN"; then
	   echo "Error. Refresh token file $FILE_REFRESH_TOKEN not found."
	   exit;
	fi
	echo "Refreshing token"
	REFRESH_TOKEN=$(< "$FILE_REFRESH_TOKEN")
	
	refresh_response=`/usr/bin/curl --request POST \
		--data "client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}&refresh_token=${REFRESH_TOKEN}&grant_type=refresh_token" \
		https://accounts.google.com/o/oauth2/token`
	#echo "refresh_response=$refresh_response"
	ACCESS_TOKEN=`echo $refresh_response | jsonValue access_token`
	if [ ! -z "$ACCESS_TOKEN" ]; then
		if test -f "$FILE_ACCESS_TOKEN"; then rm $FILE_ACCESS_TOKEN ;fi
		echo $ACCESS_TOKEN > $FILE_ACCESS_TOKEN
	else
		if [ "$RETRIES" -lt 2 ]; then
			echo "Token Refresh error. Trying all chain from beginning."
			RETRIES=$(($RETRIES + 1))
			if test -f "$FILE_REFRESH_TOKEN"; then rm $FILE_REFRESH_TOKEN ;fi
			if test -f "$FILE_ACCESS_TOKEN"; then rm $FILE_ACCESS_TOKEN ;fi

			token_chain_check
		else
			echo "Refresh error. exit"
			exit;
		fi
	fi
}

function token_chain_check() {
	if ! test -f "$FILE_ACCESS_TOKEN"; then
	   echo "Error. Access token file $FILE_ACCESS_TOKEN not found."
	   ACCESS_TOKEN_STATUS=1
	fi

	if [ "$ACCESS_TOKEN_STATUS" -eq 1 ]; then
		get_jwt_token
	fi

	ACCESS_TOKEN=$(< "$FILE_ACCESS_TOKEN")

	get_token_status

	if [ "$ACCESS_TOKEN_STATUS" -eq 2 ]; then
		refresh_access_token
	fi

	ACCESS_TOKEN=$(< "$FILE_ACCESS_TOKEN")

	if [ -z "$ACCESS_TOKEN" ]; then
	   echo "Error. Access token is empty."
	   exit;
	fi
}

function client_code_message() {
	echo "Visit url and save CLIENT_CODE to .code file."
	scope="https://www.googleapis.com/auth/drive"
	echo "https://accounts.google.com/o/oauth2/auth?client_id=${CLIENT_ID}&redirect_uri=urn:ietf:wg:oauth:2.0:oob&scope=$scope&response_type=code"
	exit
}

# ======================================================================
# ======================================================================
# ======================================================================
if [ -z "$CLIENT_CODE" ]; then
	client_code_message
fi

token_chain_check

if ! test -f "$FILE_FOLDER_ID"; then
	search_folder_id
fi
FOLDER_ID=$(< "$FILE_FOLDER_ID")

while IFS= read file
do
	MIME_TYPE=`file --brief --mime-type "$file"`
	SLUG=`basename "$file"`
	FILESIZE=$(stat -c "%s" "$file")
	FILE_FILE_ID="$DIR_VARS/$SLUG.file_id"
	
	echo "$FILE_FILE_ID"
	
	if ! test -f "$FILE_FILE_ID"; then
		search_file_id
	fi
	FILE_ID=$(< "$FILE_FILE_ID")

	if [ -z "$FILE_ID" ]; then
		postData="{\"mimeType\": \"$MIME_TYPE\",\"name\": \"$SLUG\",\"parents\": [\"${FOLDER_ID}\"]}"
		postDataSize=$(echo $postData | wc -c)
		echo "Creating file with new ID."
		uploadlink=`/usr/bin/curl \
		-X POST \
		-H "Host: www.googleapis.com" \
		-H "Authorization: Bearer ${ACCESS_TOKEN}" \
		-H "Content-Type: application/json; charset=UTF-8" \
		-H "X-Upload-Content-Type: $MIME_TYPE" \
		-H "X-Upload-Content-Length: $FILESIZE" \
		-d "$postData" \
		"https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable" \
		--dump-header - | sed -ne s/"location: "//p | tr -d '\r\n'`
	else
		echo "File with $FILE_ID will be overwritten."
		
		uploadlink=`/usr/bin/curl \
		-X PATCH \
		-H "Host: www.googleapis.com" \
		-H "Authorization: Bearer ${ACCESS_TOKEN}" \
		-H "Content-Type: application/json; charset=UTF-8" \
		-H "X-Upload-Content-Type: $MIME_TYPE" \
		-H "X-Upload-Content-Length: $FILESIZE" \
		-d "$postData" \
		"https://www.googleapis.com/upload/drive/v3/files/$FILE_ID?uploadType=resumable" \
		--dump-header - | sed -ne s/"location: "//p | tr -d '\r\n'`
		
		#echo "$uploadlink"
	fi


	if [ -z "$uploadlink" ]; then
		echo "Upload link is empty! exit"
		exit
	fi

	curl \
		-X PUT \
		-H "Authorization: Bearer ${ACCESS_TOKEN}" \
		-H "Content-Type: $MIME_TYPE" \
		-H "Content-Length: $FILESIZE" \
		-H "Slug: $SLUG" \
		--data-binary "@$file" \
		"$uploadlink"

done < $FILE_LIST

