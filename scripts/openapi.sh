#!/bin/bash

full_path=$(realpath "$0")
dir_path=$(dirname "$full_path")

if [ -z "$1" ]
  then

    installation_path="$dir_path/.."
    echo "No installation has been provided, using the default path: $installation_path"
else

    installation_path="$1"
    echo "Installation path provided: $installation_path"
fi


. "$dir_path/sdk_specs.sh"

if which openapi-generator-cli; then

  generated_path="$installation_path/lib/ff/ruby/server/generated"

  if test -e "$generated_path"; then

    if rm -rf "$generated_path"; then

      echo "'$generated_path' was removed with success 🙂"
    else

      echo "ERROR: '$generated_path' was not removed before the generation process 😬"
      exit 1
    fi
  else

    if mkdir -p "$generated_path" && test -e "$generated_path"; then

      echo "'$generated_path' has been created with success 🙂"
    else

      echo "ERROR: '$generated_path' was not created with success 😬"
      exit 1
    fi
  fi

  cd "$dir_path/.." &&
    openapi-generator-cli generate -i api.yaml -g ruby -o "$installation_path" &&
    cd "$generated_path" && gem build openapi_client.gemspec && cd .. &&
    gem install "$generated_path/openapi_client-1.0.0.gem" &&
    echo "Generated API has been installed with success: $generated_path"

else

  echo "ERROR: 'openapi-generator-cli' is not installed 😬"
  exit 1
fi
