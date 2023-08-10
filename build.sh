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
    echo -e "Done!"
}

# Define a function to write a script to a file
write_script() {
    local script_name=$1
    local script_content=$2
    local script_file="$script_dir/$script_name.sh"
    echo "$script_content" >"$script_file"
    chmod +x "$script_file"
}

DB_CONNECTION_STRING="mongodb://localhost:27017"
DATABASE_NAME="default"
SHOULD_SERVE_HEARTWOOD=true
MERCURY_ENV="default"
SKILLS_CONFIG=""
SHOULD_USE_SKILLS_CONFIG=false

# Parse arguments
for arg in "$@"; do
    case $arg in
    --databaseConnectionString=*)
        DB_CONNECTION_STRING="${arg#*=}"SHOULD
        shift
        ;;
    --databaseName=*)
        DATABASE_NAME="${arg#*=}"
        shift
        ;;
    --shouldServeHeartwood=*)
        SHOULD_SERVE_HEARTWOOD="${arg#*=}"
        shift
        ;;
    --skillsConfig=*)
        SKILLS_CONFIG="${arg#*=}"
        shift
        ;;
    --shouldUseSkillsConfig=*)
        SHOULD_USE_SKILLS_CONFIG="${arg#*=}"
        shift
        ;;
    --mercuryEnv=*)
        MERCURY_ENV="${arg#*=}"
        shift
        ;;
    *)
        shift
        ;;
    esac
done

scripts_dir="$HOME/.sprucebot"

# Create scripts directory
mkdir -p "$scripts_dir"

# Write the scripts
echo -e "Writing boot-all-skills-forever script to $scripts_dir/boot-all-skills-forever...\n"
cat <<EOF >"$scripts_dir/boot-all-skills-forever"
#!/usr/bin/env bash

screen_name="skills"
boot_command="bash $scripts_dir/boot-skill-forever"
echo "Starting boot all skills forever"
# Quit any existing screens with the same name
screen -S "\${screen_name}" -X quit

# Create a new screen session and run the skills
screen -L -d -m -S "\${screen_name}" bash
for skill_dir in *-skill; do
    echo -e "Booting \${skill_dir}"
    skill_name="\$(echo \${skill_dir} | cut -d '-' -f 2)"
    screen -S "\${screen_name}" -p 0 -X screen -t "\${skill_name}" bash -c "cd \${skill_dir} && \${boot_command}; bash"
done
EOF

echo "Writing boot-skill-forever script to $scripts_dir/boot-skill-forever..."
cat <<EOF >"$scripts_dir/boot-skill-forever"
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

mkdir platform
cd platform

DB_URL="$DB_CONNECTION_STRING"
[ "$DATABASE_NAME" == "default" ] && DB_NAME="mercury" || DB_NAME="$DATABASE_NAME"

echo "Cloning Mercury..."

git clone https://github.com/sprucelabsai/spruce-mercury-api.git

cd "spruce-mercury-api" || exit

echo "Building Mercury..."

start_time=$(date +%s)
yarn rebuild
end_time=$(date +%s)

if [[ -n "$MERCURY_ENV" && "$MERCURY_ENV" != "default" ]]; then
    echo "$MERCURY_ENV" >.env
else
    cat >.env <<EOF
SHEETS_REPORTER_ADAPTER="DummyAdapter"
DB_NAME=$DB_NAME
DB_CONNECTION_STRING=$DB_URL
MAXIMUM_LOG_PREFIXES_LENGTH=1
PORT=8081
ANONYMOUS_PERSON_PHONE=555-000-0000
DEMO_NUMBERS=*
ADMIN_NUMBERS=${PHONE_NUMBER}
DEFAULT_SENDER_DELIVERY_MECHANISM=passing
SHOULD_ENABLE_LLM=false
EOF
fi

echo "Done: $((end_time - start_time)) seconds."

cd ..

readarray -t repos <../skills.txt

clear
echo -e "Installing skills... This will take a few minutes depending on your internet connection and computer speed....\n\n"

skillCount=0

for repo in "${repos[@]}"; do

    (
        skill="$(echo ${repo} | cut -d '-' -f 2)"

        echo "Installing $skill"

        git clone https://github.com/sprucelabsai/"$repo".git

        cd "$repo" || exit

        start_time=$(date +%s)

        yarn rebuild

        if [ "$SHOULD_USE_SKILLS_CONFIG" = true ] && [ -n "$SKILLS_CONFIG" ]; then
            DB_NAME=$(jq -r ".\"$skill\".dbName" /skills.json)
            DB_CONNECTION_STRING=$(jq -r ".\"$skill\".dbConnectionString" /skills.json)
        else
            if [ "$DATABASE_NAME" != "default" ]; then
                DB_NAME="$DATABASE_NAME"
            else
                DB_NAME="$skill"
            fi
        fi

        readableSkill=$(echo "$skill" | awk '{for(i=1;i<=NF;i++)sub(/./,toupper(substr($0,i,1)),$i)}1')

        end_time=$(date +%s)

        echo "$readableSkill Installed: $((end_time - start_time)) seconds"
        echo "Continuing installation..."

        cd ..
    ) &

    ((skillCount++))

    if ((skillCount % 2 == 0)); then
        wait
    fi

done

clear
echo "Building everything..."

wait

if [ "$SHOULD_SERVE_HEARTWOOD" = true ]; then
    echo "Yay! We're almost done"
    echo "Next we need to build the Heartwood front-end!"

    cd "spruce-heartwood-skill" || exit
    yarn build.cdn

    write_alias "serve-heartwood" "echo 'Heartwod Serving at http://localhost:8080' && cd $(pwd) && python3 -m http.server 8080"

    scripts_dir="$HOME/.sprucebot"
else
    write_alias "serve-heartwood" "echo 'Heartwood serve skipped'"
fi

echo -e "Installation completed!\n"
