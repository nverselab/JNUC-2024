#!/bin/bash

OS_MAJOR=$(/usr/bin/sw_vers -productVersion | awk -F . '{print $1}')
OS_MINOR=$(/usr/bin/sw_vers -productVersion | awk -F . '{print $2}')

result=""

listSecureTokenUsers ()
{
	userList=$(dscl . list /Users name | awk '{if (substr($1,1,1) != "_") print $1}')
	for user in $userList;
	do
		enabledUser=$(sysadminctl -secureTokenStatus $user  2>&1  | awk -v user="$user" '{if ($7=="ENABLED") print user}')
		result=( "${result[@]}" "$enabledUser" )
	done
	if [ ${#result[@]} -eq 0 ]; then
		result="No users have a Secure Token"
	fi
}

if [ ${OS_MAJOR} -ge 11 ]; then
	listSecureTokenUsers
else
	result="Older macOS version."
fi

echo "<result>${result[*]}</result>"

exit 0
