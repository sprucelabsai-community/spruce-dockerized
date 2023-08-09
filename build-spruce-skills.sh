
# Define a function to write an alias
write_alias() {
    local alias_name=$1
    local alias_command=$2
    local shellrc="$HOME/.bashrc"
    if [[ $SHELL == *"zsh"* ]]; then
        shellrc="$HOME/.zshrc"
    elif [[ $SHELL == *"fish"* ]]; then
        shellrc="$HOME/.config/fish/config.fish"
    elif [[ $SHELL == *"csh"* ]]; then
        shellrc="$HOME/.cshrc"
    fi
    echo "alias $alias_name='$alias_command'" >>"$shellrc"
    echo -e "Done!\n\nRun '$alias_name' in another terminal!"
}


# Define a function to write a script to a file
write_script() {
    local script_name=$1
    local script_content=$2
    local script_file="$script_dir/$script_name.sh"
    echo "$script_content" >"$script_file"
    chmod +x "$script_file"
}


# Clone the mercury repository and set it up
if [ ! -d "spruce-mercury-api" ]; then
    echo "Cloning Mercury..."
    git clone https://github.com/sprucelabsai/spruce-mercury-api.git >>/dev/null 2>&1
    cd "spruce-mercury-api" || exit
    echo "Building Mercury..."
    start_time=$(date +%s)
    yarn rebuild >/dev/null 2>&1
    yarn build.dev >/dev/null 2>&1
    end_time=$(date +%s)
    cat <<EOF >.env
SHEETS_REPORTER_ADAPTER="DummyAdapter"
DB_NAME=mercury
DB_CONNECTION_STRING=mongodb://localhost:27017
TEST_DB_CONNECTION_STRING=mongodb://localhost:27017
MAXIMUM_LOG_PREFIXES_LENGTH=1
PORT=8081
ANONYMOUS_PERSON_PHONE=555-000-0000
DEMO_NUMBERS=*
ADMIN_NUMBERS=${PHONE_NUMBER}
DEFAULT_SENDER_DELIVERY_MECHANISM=passing
SHOULD_ENABLE_LLM=false
EOF
    echo "Done: $((end_time - start_time)) seconds."
else
    cd "spruce-mercury-api" || exit
fi

cd ..

#echo -e "Ok, Mercury is ready to rock!\n\n"
#write_alias "boot-mercury" "cd $(pwd) && yarn boot"

clear
readarray -t repos < skills.txt


clear
echo -e "Installing skills... This will take a few minutes depending on your internet connection and computer speed....\n\n"

for repo in "${repos[@]}"; do
    (
        skill="$(echo ${repo} | cut -d '-' -f 2)"
        echo "Installing $skill"
        if [ ! -d "$repo" ]; then
            git clone https://github.com/sprucelabsai/"$repo".git
        fi

        cd "$repo" || exit

        start_time=$(date +%s)

        yarn rebuild >/dev/null 2>&1
        yarn build.dev >/dev/null 2>&1

        echo "DB_NAME=\"$skill\"" >.env
        echo "DB_CONNECTION_STRING=\"mongodb://localhost:27017\"" >>.env

        readableSkill=$(echo "$skill" | awk '{for(i=1;i<=NF;i++)sub(/./,toupper(substr($0,i,1)),$i)}1')

        end_time=$(date +%s)

        echo "$readableSkill Installed: $((end_time - start_time)) seconds"
        echo "Continuing installation..."

        cd ..
    ) &
done

#Wait for all of the git clone yarn action to finish or else docker build will finish build before they're done
wait

echo "Yay! We're almost done. Next we need to build the Heartwood front-end!"

cd "spruce-heartwood-skill" || exit
yarn build.cdn >>/dev/null 2>&1


write_alias "serve-heartwood" "cd $(pwd) && python3 -m http.server 8080"

scripts_dir="$HOME/.sprucebot"

# Create scripts directory
mkdir -p "$scripts_dir"

# Write the scripts
echo "Writing boot-all-skills-forever script to $scripts_dir/boot-all-skills-forever..."
cat <<EOF >"$scripts_dir/boot-all-skills-forever"
#!/usr/bin/env bash
if [ "\$#" -eq 1 ]; then
    cd \$1
fi
while true
do
   yarn boot
done
EOF

# Make the scripts executable
chmod +x "$scripts_dir/boot-all-skills-forever"
chmod +x "$scripts_dir/boot-skill-forever"

write_alias "boot-skill-forever" "bash $scripts_dir/boot-skill-forever"
write_alias "boot-all-skills-forever" "bash $scripts_dir/boot-all-skills-forever"

echo -e "Installation completed!\n"